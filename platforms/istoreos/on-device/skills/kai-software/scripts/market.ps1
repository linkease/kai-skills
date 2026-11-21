function Market-AssertTreeNoLinks([string]$Directory){
    $queue=New-Object Collections.Queue;$queue.Enqueue($Directory)
    while($queue.Count){$next=[string]$queue.Dequeue();$item=Get-Item -LiteralPath $next -Force;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Source/cache tree contains a reparse point'};if($item.PSIsContainer){foreach($child in @(Get-ChildItem -LiteralPath $next -Force -ErrorAction Stop)){$queue.Enqueue($child.FullName)}}}
}
function Market-SourcePlan($Inventory){
    $action=[string]$request.intent
    if($action -eq 'cache-clean'){
        $cache=[string]$request.cache;if(!$cache){$cache=Join-Path $root 'cache'};$cache=Market-SafeRoot $cache
        $files=@();if(Test-Path -LiteralPath $cache){foreach($item in @(Get-ChildItem -LiteralPath $cache -Force|Sort-Object Name)){if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Cache contains a reparse point'};if(!$item.PSIsContainer -and ($item.Name -match '^[A-Za-z0-9][A-Za-z0-9._-]*#[^#]+#[^\\/]+$' -or $item.Name -match '^\.ks-cli-scoop-[0-9]+\.download$')){$files+=@{name=$item.Name;size=$item.Length;modified=$item.LastWriteTimeUtc.ToString('o')}}}}
        return @{cache=$cache;files=@($files);retains='Installed apps and Persist directories are retained'}
    }
    if($action -notin @('source-add','source-remove','refresh')){return $null}
    $name=[string]$request.source;if($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$'){throw 'An exact bucket name is required'}
    $directory=Join-Path $root ('buckets\'+$name);$exists=Test-Path -LiteralPath $directory
    if($action -eq 'source-add' -and $exists){throw 'Source already exists; use a refresh plan'}
    if($action -ne 'source-add' -and !$exists){throw 'Selected source no longer exists'}
    $files=@();if($exists){Market-AssertTreeNoLinks $directory;foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $directory 'bucket') -File -Filter '*.json'|Sort-Object Name)){$files+=@{name=$file.Name;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}}}
    $installed=@($Inventory.packages|Where-Object {$_.bucket -ceq $name}|ForEach-Object {$_.id})
    if($action -eq 'source-remove'){return @{name=$name;files=@($files);installed=@($installed);retains='Removing a source does not uninstall its applications'}}
    $git=Get-Command git -ErrorAction SilentlyContinue;if(!$git){throw 'Git is required for source management. Install scoop:main/git through a separate confirmed plan first.'}
    $url=[string]$request.url
    if($action -eq 'refresh'){
        if(Test-Path -LiteralPath (Join-Path $directory '.git')){$native=Invoke-NativeCaptured $git.Source @('-C',$directory,'remote','get-url','origin');if($native.exitCode){throw 'Cannot resolve the source remote'};$url=($native.output -join '').Trim()}
        elseif($name -ceq 'main'){$url='https://github.com/ScoopInstaller/Main'}else{throw 'Source has no verified upstream URL'}
    }
    $uri=$null;if(![Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -cne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment){throw 'Source URL must be HTTPS without credentials, query or fragment'}
    $tools=Market-ReadOnlyTools
    $resolveArgs=@('--json','scoop','bucket','resolve','--url',$url,'--policy',$script:policy)
    $useRuntime=($script:policy -ne 'none');$args=$resolveArgs
    if($useRuntime){$args=@('--json','runtime','exec','--service-binary',$tools.service,'--identity',$tools.identity,'--require-capability','route.git-github.v1','--',$tools.client)+$resolveArgs}
    $native=Invoke-NativeCaptured $tools.client $args
    if($native.exitCode -and $script:policy -eq 'auto'){
        $unavailable=@(Json-Objects ($native.output -join "`n")|Where-Object {$_.code -in @('SCOOP_RUNTIME_START_FAILED','SCOOP_RUNTIME_PORT_UNAVAILABLE')})
        if($unavailable.Count){$useRuntime=$false;$native=Invoke-NativeCaptured $tools.client $resolveArgs}
    }
    if($native.exitCode){throw ('Controlled read-only source resolution failed: '+($native.output -join "`n"))}
    $resolved=$null;$lifetime=$null
    foreach($candidate in @(Json-Objects ($native.output -join "`n"))){if($candidate.operation -eq 'bucket-resolve'){$resolved=$candidate};if($candidate.ephemeral -eq $true){$lifetime=$candidate}}
    if(!$resolved -or $resolved.status -cne 'passed' -or !$resolved.read_only -or $resolved.url -cne $url -or $resolved.acceleration_policy -cne $script:policy -or $resolved.commit -notmatch '^[0-9a-f]{40}$' -or $resolved.global_git_config_changed -ne $false){throw 'Read-only source receipt is incomplete'}
    if($script:policy -eq 'required' -and $resolved.selected -cne 'admin_proxy'){throw 'Required metadata acceleration was not proven'}
    if($useRuntime -and (!$lifetime -or $lifetime.cleanup -cne 'complete')){throw 'Metadata runtime cleanup was not proven'}
    return [ordered]@{name=$name;url=$url;commit=[string]$resolved.commit;files=@($files);installed=@($installed);route='ks-cli:scoop-bucket-fetch';acceleration=$script:policy;metadataProof=[ordered]@{readOnly=$true;selected=[string]$resolved.selected;policy=$script:policy;globalGitConfigChanged=$false};scripts='Source manifests may execute scripts when a later package plan is confirmed'}

}
function Market-ApplyMaintenance($Plan){
    if(!(Market-KnownOwner)){throw 'Prepare managed Scoop before source/cache maintenance'}
    $change=$Plan.facts.sourceChange;$action=[string]$request.intent;Market-Stage 'applying'
    if($action -eq 'cache-clean'){
        foreach($file in @($change.files)){$path=Join-Path $change.cache $file.name;Assert-Leaf $path 'Scoop cache entry';Remove-Item -LiteralPath $path -Force -ErrorAction Stop}
    }else{
        $directory=Join-Path $root ('buckets\'+$change.name)
        $staging=Join-Path $root ('buckets\.kai-source-'+[Guid]::NewGuid().ToString('N'))
        $backup=Join-Path $root ('buckets\.kai-backup-'+[Guid]::NewGuid().ToString('N'))
        $moved=$false
        try{
            if($action -ne 'source-remove'){
                $tools=Market-PrepareTools;$client=[string]$request.ksCli;Market-Stage 'downloading'
                $args=@('--json','scoop','bucket','fetch','--url',$change.url,'--commit',$change.commit,'--destination',$staging,'--policy',$script:policy)
                $useRuntime=($script:policy -ne 'none');$runtimeWarning=$null
            if($script:policy -eq 'auto'){
                $probe=Invoke-NativeCaptured $client @('--json','runtime','exec','--service-binary',[string]$request.runtimeBinary,'--identity',[string]$request.runtimeIdentity,'--require-capability','download-gateway.v1','--',$client,'--version')
                if($probe.exitCode){
                    $startupFailure=@(Json-Objects ($probe.output -join "`n")|Where-Object {$_.code -in @('SCOOP_RUNTIME_START_FAILED','SCOOP_RUNTIME_PORT_UNAVAILABLE')})
                    if(!$startupFailure.Count){throw ('Source runtime identity preflight failed: '+($probe.output -join "`n"))}
                    $useRuntime=$false;$runtimeWarning=@{status='unavailable';mode='optional';reason=($probe.output -join "`n")}
                }
            }
            if($useRuntime){$args=@('--json','runtime','exec','--service-binary',[string]$request.runtimeBinary,'--identity',[string]$request.runtimeIdentity,'--require-capability','route.git-github.v1','--',$client)+$args}
                $native=Invoke-NativeCaptured $client $args
                if($native.exitCode){throw ('Source acquisition failed: '+($native.output -join "`n"))}
                $sourceReceipt=$null
                foreach($candidate in @(Json-Objects ($native.output -join "`n"))){if($candidate.operation -eq 'bucket-fetch'){$sourceReceipt=$candidate}}
                if(!$sourceReceipt -or $sourceReceipt.status -ne 'passed' -or $sourceReceipt.commit -cne $change.commit -or $sourceReceipt.url -cne $change.url -or $sourceReceipt.acceleration_policy -cne $script:policy -or $sourceReceipt.global_git_config_changed -ne $false -or ($script:policy -eq 'required' -and $sourceReceipt.selected -cne 'admin_proxy')){throw 'Source receipt did not prove the approved acquisition'}
                Market-Stage 'verifying';Market-AssertTreeNoLinks $staging
                $manifests=@(Get-ChildItem -LiteralPath (Join-Path $staging 'bucket') -File -Filter '*.json' -ErrorAction Stop)
                if(!$manifests.Count){throw 'Source has no supported Scoop manifests'}
                foreach($manifest in $manifests){$value=Market-ReadJson $manifest.FullName;if(!(Property $value 'version')){throw 'Source contains an invalid manifest'}}
            }
            Market-Stage 'applying'
            if(Test-Path -LiteralPath $directory){[IO.Directory]::Move($directory,$backup);$moved=$true}
            if($action -ne 'source-remove'){[IO.Directory]::Move($staging,$directory)}
            if($moved){Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction Stop;$moved=$false}
        }catch{if($moved -and !(Test-Path -LiteralPath $directory)){[IO.Directory]::Move($backup,$directory)};throw}
        finally{if(Test-Path -LiteralPath $staging){Market-AssertTreeNoLinks $staging;Remove-Item -LiteralPath $staging -Recurse -Force}}
    }
    Market-Stage 'reconciling';$inventory=Market-Inventory $root
    if($action -eq 'source-remove' -and (Test-Path -LiteralPath $directory)){throw 'Removed source remains present'}
    return @{schemaVersion=1;status='passed';operation=$action;sourceChange=$change;postconditions=@{nativeReconciled=$true};inventory=$inventory;nativeReceipt=$(if($sourceReceipt){$sourceReceipt}else{@{provider='native-scoop-source';operation=$action;globalGitConfigChanged=$false;persistPreserved=$true}})}
}

function Market-Stage([string]$State) {
    if($env:KAI_MARKET_GATE_DIR){
        $directory=$env:KAI_MARKET_GATE_DIR;$gate=Join-Path $directory 'lock';$deadline=[DateTime]::UtcNow.AddSeconds(5)
        while($true){
            try{$null=New-Item -ItemType Directory -Path $gate -ErrorAction Stop;break}
            catch{if(!(Test-Path -LiteralPath $gate) -or [DateTime]::UtcNow -gt $deadline){throw 'Execution cancellation gate unavailable'};Start-Sleep -Milliseconds 10}
        }
        try{
            if(Test-Path -LiteralPath (Join-Path $directory 'cancel')){throw 'Operation cancelled at native safe point'}
            [IO.File]::WriteAllText((Join-Path $directory 'phase'),$State,[Text.UTF8Encoding]::new($false))
        }finally{[IO.Directory]::Delete($gate)}
    }
    [Console]::Error.WriteLine('KAI_MARKET_STAGE:'+ (Market-Json @{state=$State}))
}
function Market-CoreOwner($CandidateLock){
    if(!$CandidateLock){return $false};$receipt=Market-ReadJson (Join-Path $root '.linkease-scoop-receipt.json')
    if(!$receipt -or $receipt.schema_version -ne 1){return $false}
    foreach($key in @('owner','installer_version','runtime_bundle_id','runtime_bundle_sha256','core_commit','core_sha256','main_commit','main_sha256')){if([string](Property $receipt $key) -cne [string](Property $CandidateLock $key)){return $false}}
    foreach($file in @('apps\scoop\current\bin\scoop.ps1','shims\scoop.cmd')){if(!(Test-Path -LiteralPath (Join-Path $root $file) -PathType Leaf)){return $false}}
    return $true
}
function Market-KnownOwner {
    if(Market-CoreOwner $lock){return $true}
    $supported=Market-ReadJson (Join-Path $PSScriptRoot '..\resources\supported-scoop-owners.json')
    foreach($previous in @($supported)){if($previous -and (Market-CoreOwner $previous)){return $true}}
    return $false
}

function Market-Helpers($Manifest, [string]$Architecture = $script:architecture) {
    $helpers=@();$urls=@(Effective $Manifest 'url' $Architecture)
    if(@($urls|Where-Object {[string]$_ -match '\.(001|7z|bz(ip)?2?|gz|img|iso|lzma|lzh|nupkg|rar|tar|t[abgpx]z2?|t?zst|xz)(\.[^\d.]+)?$'}).Count){$helpers+='main/7zip'}
    if(@($urls|Where-Object {[string]$_ -match '\.msi$'}).Count){$helpers+='main/lessmsi'}
    $installer=Effective $Manifest 'installer' $Architecture;$scripts=@((Effective $Manifest 'pre_install' $Architecture),(Property $installer 'script'),(Effective $Manifest 'post_install' $Architecture)) -join "`n"
    if($null -ne (Effective $Manifest 'innosetup' $Architecture) -or $scripts -like '*Expand-InnoArchive *'){$helpers+='main/innounp'}
    if($scripts -like '*Expand-DarkArchive *'){$helpers+='main/dark'}
    return @($helpers|Select-Object -Unique)
}
function Market-ExecutePackage($Item,$Plan) {
    $target=$Item.packageId.Substring(6);$action=[string]$Item.action;if(!$action){$action=[string]$request.intent}
    if($action -in @('install','update')){
        $client=[string]$request.ksCli
        $explain=Invoke-NativeCaptured $client @('--explain','--json','scoop',$action,'--architecture',$script:architecture,'--policy',$script:policy,$target)
        if($explain.exitCode){return @{id=$Item.packageId;status='failed';category='resolve-failed';nativeExitCode=$explain.exitCode;output=($explain.output -join "`n")}}
        $resolved=($explain.output -join "`n")|ConvertFrom-Json
        if(!$resolved.read_only -or !$resolved.plan_sha256){throw 'Native CLI did not return a bound read-only plan'}
        foreach($package in @($resolved.plan.packages)){
            $approved=@($Plan.facts.items|Where-Object {$_.packageId -ceq ('scoop:'+$package.identity)})
            if($approved.Count -ne 1 -or $approved[0].manifestSHA256 -cne $package.manifest_sha256 -or $approved[0].version -cne $package.version){throw ('Native dependency or manifest changed: '+$package.identity)}
        }
        $receiptPath=Join-Path ([string]$request.toolsRoot) ('package-'+[Guid]::NewGuid().ToString('N')+'.json')
        try{
            $args=@('--json','scoop',$action,'--architecture',$script:architecture,'--policy',$script:policy,'--expected-plan-sha256',$resolved.plan_sha256,'--receipt',$receiptPath,$target)
            $useRuntime=($script:policy -ne 'none');$runtimeWarning=$null
            if($script:policy -eq 'auto'){
                $probe=Invoke-NativeCaptured $client @('--json','runtime','exec','--service-binary',[string]$request.runtimeBinary,'--identity',[string]$request.runtimeIdentity,'--require-capability','download-gateway.v1','--',$client,'--version')
                if($probe.exitCode){
                    $startupFailure=@(Json-Objects ($probe.output -join "`n")|Where-Object {$_.code -in @('SCOOP_RUNTIME_START_FAILED','SCOOP_RUNTIME_PORT_UNAVAILABLE')})
                    if(!$startupFailure.Count){return @{id=$Item.packageId;status='failed';category='runtime-preflight-failed';nativeExitCode=$probe.exitCode;output=($probe.output -join "`n")}}
                    $useRuntime=$false;$runtimeWarning=@{status='unavailable';mode='optional';reason=($probe.output -join "`n")}
                }
            }
            if($useRuntime){$args=@('--json','runtime','exec','--service-binary',[string]$request.runtimeBinary,'--identity',[string]$request.runtimeIdentity,'--require-capability','download-gateway.v1','--',$client)+$args}
            $native=Invoke-NativeCaptured $client $args
            if($native.exitCode){return @{id=$Item.packageId;status='failed';category='native-package-failed';nativeExitCode=$native.exitCode;output=($native.output -join "`n")}}
            $receipt=Market-ReadJson $receiptPath;Assert-PayloadReceipt $receipt $action $target
            $runtimeReceipt=$null
            if($useRuntime){
                foreach($candidate in @(Json-Objects ($native.output -join "`n"))){if($candidate.ephemeral -eq $true){$runtimeReceipt=$candidate}}
                if(!$runtimeReceipt -or $runtimeReceipt.status -ne 'passed' -or $runtimeReceipt.cleanup -ne 'complete'){throw 'Package runtime cleanup receipt missing'}
            }
            return @{id=$Item.packageId;status='passed';nativeReceipt=$receipt;runtime=$runtimeReceipt;runtimeWarning=$runtimeWarning}
        }finally{Remove-Item -LiteralPath $receiptPath -Force -ErrorAction SilentlyContinue}
    }
    $parts=Parse-Identity $target
    $hostPS=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $core=Join-Path $root 'apps\scoop\current\bin\scoop.ps1'
    Market-Stage 'applying'
    $command=if($action -eq 'remove'){'uninstall'}else{$action}
    $isolated=Join-Path ([IO.Path]::GetTempPath()) ('kai-scoop-market-config-'+[Guid]::NewGuid().ToString('N'));$configuration=Join-Path $isolated 'scoop'
    New-Item -ItemType Directory -Path $configuration -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $configuration 'config.json'),(Market-Json @{no_junction=$true;use_lessmsi=$true;last_update=[DateTime]::UtcNow.ToString('o')}),[Text.UTF8Encoding]::new($false))
    $previousXDG=$env:XDG_CONFIG_HOME;$env:XDG_CONFIG_HOME=$isolated
    try{$native=Invoke-NativeCaptured $hostPS @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$core,$command,$parts[1])}
    finally{$env:XDG_CONFIG_HOME=$previousXDG;Remove-Item -LiteralPath $isolated -Recurse -Force -ErrorAction SilentlyContinue}
    if($native.exitCode){return @{id=$Item.packageId;status='failed';category='native-package-failed';nativeExitCode=$native.exitCode;output=($native.output -join "`n")}}
    return @{id=$Item.packageId;status='passed';nativeReceipt=@{provider='native-scoop';operation=$action;exitCode=0;persistPreserved=($action -eq 'remove')}}
}
function Market-ApplyPackages($Plan){
    $bootstrap=$null
    $tools=$null
    if($request.intent -in @('install','update')){
        if(!(Market-CompatibleOwner)){$bootstrap=Market-ApplySetup $Plan}
        $tools=Market-PrepareTools
    }
    $env:SCOOP_CACHE=[string]$Plan.facts.cache;$env:KSCLI_SCOOP_EVENTS='1'
    $results=@()
    $ordered=@($Plan.facts.items)
    if($request.intent -in @('install','update','remove')){$ordered=@(Market-OrderItems $Plan.facts.items);if($request.intent -eq 'remove'){[array]::Reverse($ordered)}}
    $failed=@{};$stopped=$false
    foreach($item in $ordered){
        $dependencyFailed=$false
        if($request.intent -eq 'remove'){
            foreach($retained in $ordered){if(!$failed.ContainsKey($retained.packageId)){continue};foreach($dependency in @($retained.dependencies)){$id=[string]$dependency;if(!$id.Contains('/')){$id='main/'+$id};if(('scoop:'+$id) -ceq $item.packageId){$dependencyFailed=$true}}}
        }else{foreach($dependency in @($item.dependencies)){$id=[string]$dependency;if(!$id.Contains('/')){$id='main/'+$id};if($failed.ContainsKey('scoop:'+$id)){$dependencyFailed=$true;break}}}
        if($stopped -or $dependencyFailed){$result=@{id=$item.packageId;status='skipped';category=$(if($stopped){'stop-on-first-failure'}elseif($request.intent -eq 'remove'){'retained-dependent'}else{'dependency-failed'})}}
        elseif($item.action -eq 'reuse'){$result=@{id=$item.packageId;status='passed';reused=$true}}
        else {try {$result=Market-ExecutePackage $item $Plan} catch {$result=@{id=$item.packageId;status='failed';category='native-package-failed';output=$_.Exception.Message}}}
        $results+=,$result
        if($result.status -ne 'passed'){$failed[$item.packageId]=$true;if([bool]$request.stopOnFailure){$stopped=$true}}
    }
    Market-Stage 'reconciling'
    $inventoryKnown=$true
    try{$inventory=Market-Inventory $root}catch{$inventoryKnown=$false;$inventory=@{status='unknown';reason=$_.Exception.Message}}
    $valid=$true;$reason='';$code=0
    foreach($result in $results){
        if($result.status -ne 'passed'){$valid=$false;$reason=[string]$result.category;$code=[int]$result.nativeExitCode;continue}
        $row=@($inventory.packages|Where-Object {$_.id -ceq $result.id});$approved=@($Plan.facts.items|Where-Object {$_.packageId -ceq $result.id})[0]
        $action=[string]$request.intent
        if($action -eq 'remove'){
            $parts=Parse-Identity ($result.id.Substring(6))
            if($row.Count -or (Test-Path -LiteralPath (Join-Path $root ('apps\'+$parts[1])))){$valid=$false;$reason='remove-incomplete'}
        }elseif($row.Count -ne 1){$valid=$false;$reason='native-postcondition-failed'}
        elseif($action -in @('install','update') -and $row[0].installedVersion -cne $approved.version){$valid=$false;$reason='native-version-mismatch'}
        elseif(($action -eq 'hold' -and !$row[0].held) -or ($action -eq 'unhold' -and $row[0].held)){$valid=$false;$reason='native-hold-mismatch'}
    }
    if($results.Count -ne $ordered.Count -or !$inventoryKnown){$valid=$false;if(!$reason){$reason='inventory-unresolved'}}
    return @{schemaVersion=1;status=$(if($valid){'passed'}else{'failed'});operation=[string]$request.intent;category=$reason;nativeExitCode=$code;items=@($results);inventoryKnown=$inventoryKnown;bootstrap=$bootstrap;tools=$tools;postconditions=@{nativeReconciled=$inventoryKnown};inventory=$inventory}
}

# Native market contract. Dot-sourced by the verified Scoop adapter.
function Market-Hash([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
}
function Market-Json($Value) { return ConvertTo-Json -InputObject $Value -Depth 40 -Compress }
function Market-ReadJson([string]$Path) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Market-SafeRoot([string]$Root) {
    $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Root)).TrimEnd('\')
    $profile = [IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')
    if (!$full.StartsWith($profile + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Installation and cache paths must stay inside the current user profile.' }
    $probe = $full
    while ($probe) {
        if (Test-Path -LiteralPath $probe) { if ((Get-Item -LiteralPath $probe -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Installation path contains a reparse point.' } }
        $parent = Split-Path -Parent $probe; if ($parent -eq $probe) { break }; $probe = $parent
    }
    return $full
}
function Market-VersionState([string]$Installed,[string]$Available){
    if(!$Available){return 'source-missing'}
    if($Installed -ceq $Available){return 'current'}
    if($Installed -match '(?i)nightly|latest' -or $Available -match '(?i)nightly|latest'){return 'unknown'}
    $versions=Join-Path $root 'apps\scoop\current\lib\versions.ps1'
    if(!(Test-Path -LiteralPath $versions -PathType Leaf)){return 'unknown'}
    Assert-Leaf $versions 'Native version comparison'
    $errors=$null;$tokens=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($versions,[ref]$tokens,[ref]$errors)
    if($errors.Count){return 'unknown'}
    foreach($definition in $ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -in @('Compare-Version','SplitVersion')}){. ([scriptblock]::Create($definition.Extent.Text))}
    try{$comparison=Compare-Version -ReferenceVersion $Installed -DifferenceVersion $Available;if($comparison -gt 0){return 'newer'};if($comparison -lt 0){return 'older'};return 'current'}catch{return 'unknown'}
}
function Market-UpdateRisks($Installed,$Manifest,[string]$Architecture){
    $risks=@();$old=[string]$Installed.installedVersion;$new=[string]$Manifest.version
    if($old -notmatch '^v?\d+([.][0-9]+)*$' -or $new -notmatch '^v?\d+([.][0-9]+)*$'){$risks+='nonstandard-version'}
    elseif([long]($new -replace '^v?(\d+).*','$1') -gt [long]($old -replace '^v?(\d+).*','$1')){$risks+='major-version'}
    $installedArchitecture=[string]$Installed.architecture;if(!$installedArchitecture){$installedArchitecture=$Architecture}
    if($installedArchitecture -cne $Architecture){$risks+='architecture-changed'}
    foreach($key in @('pre_install','post_install','pre_uninstall','post_uninstall','installer','uninstaller','env_add_path','env_set','persist','depends')){
        if((Market-Json (Effective $Installed.manifest $key $installedArchitecture)) -cne (Market-Json (Effective $Manifest $key $Architecture))){$risks+=('changed:'+ $key)}
    }
    return @($risks)
}
function Market-Inventory([string]$Root) {
    if (!(Market-KnownOwner)) {
        if (Test-Path -LiteralPath $Root) { throw 'Scoop ownership does not match the supported zsetup receipt. Existing files are preserved.' }
        return [ordered]@{status='absent';packages=@()}
    }
    $rows = @()
    foreach ($app in @(Get-ChildItem -LiteralPath (Join-Path $Root 'apps') -Directory -Force -ErrorAction Stop | Sort-Object Name)) {
        if ($app.Name -eq 'scoop') { continue }
        $current = Join-Path $app.FullName 'current'
        if (!(Test-Path -LiteralPath $current -PathType Container)) {
            # Native no_junction installs identify the selected version by the
            # installation metadata timestamp, not a directory-name version sort.
            $versions=@()
            foreach($directory in @(Get-ChildItem -LiteralPath $app.FullName -Directory -Force -ErrorAction Stop)){
                if($directory.Name -eq 'current' -or $directory.Name -like '_*.old*'){continue}
                if($directory.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Installed version directory is an unexpected reparse point'}
                foreach($metadata in @('scoop-install.json','install.json')){$path=Join-Path $directory.FullName $metadata;if(Test-Path -LiteralPath $path -PathType Leaf){Assert-Leaf $path 'Installed version metadata';$versions+=@{path=$directory.FullName;at=(Get-Item -LiteralPath $path).LastWriteTimeUtc};break}}
            }
            # Hashtable keys are not adapted Sort-Object properties in Windows PS 5.1.
            $versions=@($versions|Sort-Object {$_.at})
            if(!$versions.Count){throw ('Native installation metadata is unresolved: '+$app.Name)}
            if($versions.Count -gt 1 -and $versions[-1].at -eq $versions[-2].at){throw ('Native selected version is ambiguous: '+$app.Name)}
            $current=[string]$versions[-1].path
        }
        $currentItem=Get-Item -LiteralPath $current -Force
        if($currentItem.Attributes -band [IO.FileAttributes]::ReparsePoint){$targets=@($currentItem.Target);if($targets.Count -ne 1 -or !([IO.Path]::GetFullPath([string]$targets[0])).StartsWith($app.FullName+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Installed current version points outside its application directory'}}
        $manifest = Market-ReadJson (Market-InstalledManifestPath $current)
        $install = Market-ReadJson (Join-Path $current 'install.json')
        if (!$install) { $install = Market-ReadJson (Join-Path $current 'scoop-install.json') }
        if (!$manifest -or !(Property $manifest 'version')) { throw ('Cannot parse installed manifest: ' + $app.Name) }
        $bucket = [string](Property $install 'bucket')
        $identity = if ($bucket -match '^[A-Za-z0-9][A-Za-z0-9._-]*$') { 'scoop:' + $bucket + '/' + $app.Name } else { 'unresolved:' + $app.Name }
        $available = $null
        if ($bucket) { $available = Market-ReadJson (Join-Path $Root ('buckets\'+$bucket+'\bucket\'+$app.Name+'.json')) }
        $held = [bool](Property $install 'hold')
        $versionState=Market-VersionState ([string]$manifest.version) ([string](Property $available 'version'))
        $rows += [ordered]@{id=$identity;name=$app.Name;installed=$true;installedVersion=[string]$manifest.version;availableVersion=[string](Property $available 'version');bucket=$bucket;root=$current;architecture=[string](Property $install 'architecture');persist=(Join-Path $Root ('persist\'+$app.Name));held=$held;sourceMissing=($null -eq $available);manifest=$manifest;versionState=$versionState;updateRisks=$(if($versionState -eq 'newer'){@(Market-UpdateRisks ([pscustomobject]@{installedVersion=[string]$manifest.version;manifest=$manifest;architecture=[string](Property $install 'architecture')}) $available $script:architecture)}else{@()});updateAvailable=($versionState -eq 'newer' -and !$held)}
    }
    return [ordered]@{status='ready';packages=@($rows)}
}
function Market-Catalog {
    if (!(Market-KnownOwner)) {Emit @{status='absent';packages=@();sources=@()};return}
    $rows=@();$sources=@();$warnings=@()
    foreach($bucket in @(Get-ChildItem -LiteralPath (Join-Path $root 'buckets') -Directory -Force -ErrorAction Stop|Sort-Object Name)) {
        if($bucket.Name -match '^\.kai-(source|backup)-[0-9a-f]{32}$'){
            if($bucket.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Interrupted source directory is a reparse point'}
            $warnings+=('Interrupted source transaction retained: '+$bucket.Name+'. Inspect the failed operation before cleanup or a new source plan.');continue
        }
        if($bucket.Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or ($bucket.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unsafe bucket directory'}
        $directory=Join-Path $bucket.FullName 'bucket';if(!(Test-Path -LiteralPath $directory -PathType Container)){throw ('Missing bucket manifests: '+$bucket.Name)}
        $remote='';$commit='';$kind='third-party'
        $gitConfig=Join-Path $bucket.FullName '.git\config'
        if(Test-Path -LiteralPath $gitConfig){$config=[IO.File]::ReadAllText($gitConfig);$match=[regex]::Match($config,'(?m)^\s*url\s*=\s*(https://[^\s]+)\s*$');if($match.Success){$remote=$match.Groups[1].Value}}
        if(Test-Path -LiteralPath (Join-Path $bucket.FullName '.git')){
            $head=@(& git -C $bucket.FullName rev-parse --verify HEAD 2>$null);$gitCode=$LASTEXITCODE
            if($gitCode -ne 0 -or $head.Count -ne 1 -or ([string]$head[0]).Trim() -notmatch '^[0-9a-f]{40}$'){throw ('Source commit is unresolved: '+$bucket.Name)}
            $commit=([string]$head[0]).Trim().ToLowerInvariant()
        }
        if($bucket.Name -ceq 'main' -and !$remote){$remote='https://github.com/ScoopInstaller/Main';$commit=[string]$lock.main_commit;$kind='official-pinned'}
        elseif($remote -match '^https://github.com/ScoopInstaller/(Main|Extras)(?:\.git)?$'){$kind='official'}
        $count=0
        foreach($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File -ErrorAction Stop|Sort-Object Name)) {
            Assert-Leaf $file.FullName 'Bucket manifest'
            $raw=[IO.File]::ReadAllText($file.FullName);$manifest=$raw|ConvertFrom-Json -ErrorAction Stop
            if(!(Property $manifest 'version')){throw ('Unreadable manifest version: '+$file.Name)}
            $archs=Property $manifest 'architecture';$architectures=if($archs){@($archs.PSObject.Properties.Name)}else{@('64bit','32bit','arm64')}
            $rows+=[ordered]@{id=('scoop:'+$bucket.Name+'/'+$file.BaseName);name=$file.BaseName;description=[string](Property $manifest 'description');availableVersion=[string]$manifest.version;bucket=$bucket.Name;homepage=[string](Property $manifest 'homepage');license=(Property $manifest 'license');architectures=@($architectures);manifestSHA256=(Market-Hash $raw);rawManifest=$raw};$count++
        }
        $sources+=[ordered]@{name=$bucket.Name;url=$remote;kind=$kind;commit=$commit;manifestCount=$count;lastObserved=[DateTime]::UtcNow.ToString('o');health='ready'}
    }
    Emit @{schemaVersion=1;status='ready';source='native-scoop-buckets';packages=@($rows);sources=@($sources);warnings=@($warnings)}
}
function Market-Elevated {
    return ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Market-Manifest([string]$ID) {
    $parts = Parse-Identity ($ID.Substring(6)); $path = Join-Path $root ('buckets\'+$parts[0]+'\bucket\'+$parts[1]+'.json')
    if (Test-Path -LiteralPath $path -PathType Leaf) { return [IO.File]::ReadAllText($path) }
    $preview = Property $request 'previewManifests'; $raw = Property $preview $ID
    if ($parts[0] -eq 'main' -and $raw -and !(Market-KnownOwner)) { return [string]$raw }
    throw ('Exact source manifest is unavailable: '+$ID)
}
function Market-Capability {
    $owned=Market-KnownOwner
    $reason='';$status='absent';$inventory=$null
    try {$null=Market-SafeRoot $root;if($owned){$inventory=Market-Inventory $root}} catch {$status='blocked';$reason=$_.Exception.Message}
    $toolsRoot=[string](Property $request 'toolsRoot')
    $prepared=$false;$client=[string](Property $request 'ksCli');$zsetup=[string](Property $request 'zsetup')
    if($toolsRoot){
        $archive=Join-Path $toolsRoot 'runtime.zip';$runtime=Join-Path $toolsRoot $lock.runtime_bundle_id
        if((Test-Path -LiteralPath $archive -PathType Leaf) -and (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ieq $lock.runtime_bundle_sha256){
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $trusted=[IO.Compression.ZipFile]::OpenRead($archive)
            try {$reader=[IO.StreamReader]::new($trusted.GetEntry('manifest.json').Open());try {$meta=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}}finally{$trusted.Dispose()}
            $prepared=($meta -and $meta.bundle_id -ceq $lock.runtime_bundle_id -and $meta.files.Count -eq 3)
            if($prepared){foreach($record in $meta.files){if(@('identity.json','ks-cli.exe','kspeeder.exe') -cnotcontains $record.path){$prepared=$false;break};$file=Join-Path $runtime $record.path;if(!(Test-Path -LiteralPath $file -PathType Leaf) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $record.sha256){$prepared=$false;break}}}
            if($prepared){$client=Join-Path $runtime 'ks-cli.exe'}
        }
        if(!$zsetup){$zsetup=Join-Path $toolsRoot 'rescue\0.6.5\zsetup.exe'}
    }
    $cliReady=$prepared -and $client -and (Test-Path -LiteralPath $client -PathType Leaf)
    $zsetupReady=$zsetup -and (Test-Path -LiteralPath $zsetup -PathType Leaf) -and (Get-FileHash -LiteralPath $zsetup -Algorithm SHA256).Hash -ieq '07d99ebcaae8739e95d92a510891dd729f7f9da52f898bb19a4360fe6f01ac06'
    if($status -ne 'blocked'){
        if($owned){$status=if($cliReady -and $prepared){'ready'}else{'degraded'}}
        elseif((Test-Path -LiteralPath $root) -or (Get-Command scoop -ErrorAction SilentlyContinue)){$status='blocked';$reason='Existing Scoop requires ownership verification; automatic adoption is refused.'}
    }
    if(!$reason){$reason=if($prepared){'Verified task runtime is prepared; it starts for operations and stops after completion. No Windows service is installed.'}else{'Required managed tools need preparation; no running KSpeeder service is implied.'}}
    $result=[ordered]@{schemaVersion=1;status=$status;platform='windows';provider='scoop';root=$root;cache=$(if([string](Property $request 'cache')){[string]$request.cache}else{Join-Path $root 'cache'});architecture=$script:architecture;reason=$reason;dependencies=@(
        [ordered]@{id='scoop';version=$(if($owned){[string](Market-ReadJson (Join-Path $root '.linkease-scoop-receipt.json')).core_commit}else{''});path=(Join-Path $root 'apps\scoop\current\bin\scoop.ps1');state=$(if($owned){'ready'}elseif($status -eq 'blocked'){'blocked'}else{'missing'})},
        [ordered]@{id='zsetup';version=$(if($zsetupReady){'0.6.5'}else{''});path=$zsetup;state=$(if($zsetupReady){'ready'}else{'missing'})},
        [ordered]@{id='ks-cli';version=$(if($prepared){[string]$meta.compatibility.ks_cli_commit}else{''});path=$client;state=$(if($cliReady){'ready'}else{'missing'})},
        [ordered]@{id='kspeeder';version=$(if($prepared){[string]$meta.version}else{''});path=$(if($prepared){Join-Path $runtime 'kspeeder.exe'}else{''});state=$(if($prepared){'ready'}else{'missing'});detail='Task-scoped runtime; ready to start, not a resident service'}
    );evidenceTime=[DateTime]::UtcNow.ToString('o')}
    if($inventory -and $inventory.status -eq 'ready'){$result['installedCount']=@($inventory.packages).Count;$result['updateCount']=@($inventory.packages|Where-Object {$_.updateAvailable}).Count}
    Emit $result
}
function Market-EmptyInstallPlan {
    if(!(Market-KnownOwner)){throw 'Managed Scoop ownership is required for interrupted-install recovery'}
    $ids=@($request.packages);if($ids.Count -ne 1){throw 'Select one exact interrupted package'}
    $id=[string]$ids[0];$parts=Parse-Identity ($id.Substring(6));$app=Join-Path $root ('apps\'+$parts[1])
    if(!(Test-Path -LiteralPath $app -PathType Container)){throw 'Interrupted application directory is no longer present'}
    Market-AssertTreeNoLinks $app
    $empty=@()
    foreach($entry in @(Get-ChildItem -LiteralPath $app -Force -ErrorAction Stop)){
        if(!$entry.PSIsContainer -or $entry.Name -eq 'current' -or $entry.Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$' -or @(Get-ChildItem -LiteralPath $entry.FullName -Force -ErrorAction Stop).Count){throw 'Recovery only removes proven empty version directories; existing files are preserved for diagnosis'}
        $empty+=$entry.Name
    }
    $empty=@($empty|Sort-Object)
    $cache=[string](Property $request 'cache');if(!$cache){$cache=Join-Path $root 'cache'};$cache=Market-SafeRoot $cache
    $facts=[ordered]@{targetId='local';root=$root;cache=$cache;architecture=$script:architecture;policy=$script:policy;allowAdmin=[bool]$request.allowAdmin;elevated=(Market-Elevated);owner=(Market-ReadJson (Join-Path $root '.linkease-scoop-receipt.json'));items=@();emptyInstall=@{packageId=$id;application=$parts[1];directories=@($empty);persistPreserved=$true};inventory=@{status='unknown';reason='Interrupted empty installation'}}
    return [ordered]@{schemaVersion=1;status='planned';fingerprint=(Market-Hash (Market-Json $facts));facts=$facts;risks=@('Remove only empty interrupted version/application directories. Persist, user data, shims and all nonempty directories are preserved.');route=@('native-scoop-provider');bootstrapRequired=$false}
}
function Market-ApplyEmptyInstall($Plan){
    $approved=$Plan.facts.emptyInstall;$app=Join-Path $root ('apps\'+$approved.application)
    foreach($name in @($approved.directories)){[IO.Directory]::Delete((Join-Path $app $name),$false)}
    [IO.Directory]::Delete($app,$false)
    Market-Stage 'reconciling';$known=$true
    try{$inventory=Market-Inventory $root}catch{$known=$false;$inventory=@{status='unknown';reason=$_.Exception.Message}}
    return @{schemaVersion=1;status=$(if($known){'passed'}else{'failed'});category=$(if(!$known){'inventory-unresolved'}else{''});inventoryKnown=$known;operation='repair-empty-install';emptyInstall=$approved;postconditions=@{nativeReconciled=$known;persistPreserved=$true};inventory=$inventory;nativeReceipt=@{provider='native-scoop';emptyDirectoriesOnly=$true}}
}
function Market-Plan {
    $intent = [string]$request.intent
    if($intent -eq 'repair-empty-install'){return (Market-EmptyInstallPlan)}
    $hostArchitecture=if($env:PROCESSOR_ARCHITEW6432){$env:PROCESSOR_ARCHITEW6432}else{$env:PROCESSOR_ARCHITECTURE}
    if($intent -in @('install','update','setup') -and (($script:architecture -eq 'arm64' -and $hostArchitecture -notmatch '^(?i:arm64)$') -or ($script:architecture -eq '64bit' -and $hostArchitecture -match '^(?i:x86)$'))){throw 'Selected package architecture cannot run on this Windows device'}
    $inventory = Market-Inventory $root
    if ($inventory.status -eq 'absent') {
        $existing = Get-Command scoop -ErrorAction SilentlyContinue
        if ($existing) { throw 'Another Scoop is on PATH. Select and verify its installation root; automatic adoption or PATH replacement is refused.' }
    }
    $cache = [string](Property $request 'cache'); if (!$cache) { $cache = Join-Path $root 'cache' }
    $cache = Market-SafeRoot $cache
    if ($cache -eq $root -or $root.StartsWith($cache+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Cache cannot contain the installation root.' }
    $items = @(); $seen = @{}; $names=@{}; $queue = New-Object Collections.Queue
    foreach ($id in @($request.packages)) { if ($id) {$queue.Enqueue([string]$id)} }
    while ($queue.Count -gt 0) {
        $id = [string]$queue.Dequeue(); if ($seen.ContainsKey($id)) { continue }; $seen[$id]=$true
        $parts = Parse-Identity ($id.Substring(6))
        if($names.ContainsKey($parts[1]) -and $names[$parts[1]] -ine $id){throw 'Two buckets cannot own the same Scoop application name in one plan'};$names[$parts[1]]=$id
        $installed = @($inventory.packages | Where-Object {$_.id -ceq $id})
        $otherSource=@($inventory.packages|Where-Object {$_.name -ieq $parts[1] -and $_.id -cne $id});if($otherSource.Count){throw ('Scoop application name is already owned by '+$otherSource[0].id+'. Manage or remove that exact installation first.')}
        if($intent -in @('remove','hold','unhold') -and $installed.Count){$raw=[IO.File]::ReadAllText((Market-InstalledManifestPath $installed[0].root))}else{$raw=Market-Manifest $id}
        $manifest=$raw | ConvertFrom-Json
        $archs = Property $manifest 'architecture'
        if ($intent -in @('install','update') -and $archs -and !(Property $archs $script:architecture)) { throw ('Selected architecture unavailable: '+$id) }
        if ($intent -in @('update','remove','hold','unhold') -and $id -in @($request.packages) -and $installed.Count -eq 0) { throw ('Exact package is not installed: '+$id) }
        if ($intent -eq 'update' -and $installed.Count -and $installed[0].held) { throw ('Package is held: '+$id) }
        $itemArchitecture=$script:architecture
        if($intent -in @('remove','hold','unhold') -and $installed.Count -and $installed[0].architecture){$itemArchitecture=[string]$installed[0].architecture}
        $scripts = [ordered]@{}
        foreach ($key in @('pre_install','post_install','pre_uninstall','post_uninstall','installer','uninstaller')) { $value=Effective $manifest $key $itemArchitecture; if ($null -ne $value) {$scripts[$key]=$value} }
        $dependencies = @((@(Property $manifest 'depends')+@(Market-Helpers $manifest $itemArchitecture))|Where-Object {$_}|Select-Object -Unique)
        if ($intent -in @('install','update')) { foreach ($dep in $dependencies) { if ($dep) {$qualified=[string]$dep;if (!$qualified.Contains('/')) {$qualified='main/'+$qualified};$queue.Enqueue('scoop:'+$qualified)} } }
        $itemAction=$intent
        $updateRisks=@()
        if($intent -in @('install','update')){
            if(!$installed.Count){$itemAction='install'}else{
                $direction=Market-VersionState $installed[0].installedVersion ([string]$manifest.version)
                if($direction -in @('older','unknown','source-missing')){throw ('Update direction is not proven newer: '+$id+'. Refresh its source and review the installed version.')}
                if($direction -eq 'newer'){if($installed[0].held){throw ('Dependency is held: '+$id)};$itemAction='update';$updateRisks=@(Market-UpdateRisks $installed[0] $manifest $itemArchitecture)}else{$itemAction='reuse'}
            }
        }
        $items += [ordered]@{action=$itemAction;packageId=$id;version=[string]$manifest.version;installedVersion=$(if($installed.Count){$installed[0].installedVersion}else{''});manifestSHA256=(Market-Hash $raw);manifest=$manifest;architecture=$itemArchitecture;dependencies=@($dependencies);scripts=$scripts;previousManifest=$(if($installed.Count){$installed[0].manifest}else{$null});previousArchitecture=$(if($installed.Count){$installed[0].architecture}else{''});updateRisks=@($updateRisks);persist=@(Effective $manifest 'persist' $itemArchitecture);hashes=@(Effective $manifest 'hash' $itemArchitecture);urls=@(Effective $manifest 'url' $itemArchitecture);homepage=[string](Property $manifest 'homepage');license=(Property $manifest 'license')}
        if ($seen.Count -gt 100) { throw 'Dependency closure exceeds the safe plan limit.' }
    }
    if($intent -in @('install','update')){$null=@(Market-OrderItems $items)}
    $reverseDependents=@()
    if($intent -eq 'remove'){
        $selectedIDs=@($items|ForEach-Object {$_.packageId})
        foreach($row in @($inventory.packages)){
            foreach($dependency in @(Property $row.manifest 'depends')){
                if(!$dependency){continue};$dep=[string]$dependency;if(!$dep.Contains('/')){$dep='main/'+$dep}
                if(('scoop:'+$dep) -cin $selectedIDs){$reverseDependents+=,$row;if($row.id -cnotin $selectedIDs){throw ('Package is still required by '+$row.id+'. Include its dependent in the uninstall plan first.')}}
            }
        }
        $null=@(Market-OrderItems $items)
    }

    $owner = Market-ReadJson (Join-Path $root '.linkease-scoop-receipt.json')
    $sourceChange=Market-SourcePlan $inventory
    # Only facts that can affect these packages invalidate their confirmation.
    # Shared commands, shortcuts and environment keys remain guarded even when
    # another package has a different source-qualified identity.
    $boundInventory=$inventory
    $sharedNamespace=@()
    if($intent -in @('install','update','remove','hold','unhold')){
        $namespaces=@{};$related=@{}
        foreach($item in $items){$related[$item.packageId]=$true;foreach($key in @(Market-Namespaces $item.manifest)){$namespaces[$key]=$true}}
        $bound=@($reverseDependents)
        foreach($row in @($inventory.packages)){
            $overlap=$related.ContainsKey($row.id)
            if(!$overlap){foreach($key in @(Market-Namespaces $row.manifest)){if($namespaces.ContainsKey($key)){$overlap=$true;break}}}
            if($overlap){$bound+=,$row}
        }
        $boundInventory=[ordered]@{status=$inventory.status;packages=@($bound)}
        foreach($key in @($namespaces.Keys|Sort-Object)){
            if($key.StartsWith('bin:')){
                $name=$key.Substring(4)
                foreach($ext in @('','.exe','.cmd','.ps1','.shim')){
                    $path=Join-Path $root ('shims\'+$name+$ext)
                    if(Test-Path -LiteralPath $path -PathType Leaf){Assert-Leaf $path 'Shared Scoop command';$sharedNamespace+=@{name=$name+$ext;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}}
                }
            }
        }
    }
    $sourceBindings=@()
    foreach($bucket in @($items|ForEach-Object {($_.packageId.Substring(6).Split('/'))[0]}|Sort-Object -Unique)){
        $config=Join-Path $root ('buckets\'+$bucket+'\.git\config')
        $head=Join-Path $root ('buckets\'+$bucket+'\.git\HEAD')
        $binding=[ordered]@{name=$bucket;url='';configSHA256='';headSHA256=''}
        foreach($file in @(@{path=$config;key='configSHA256'},@{path=$head;key='headSHA256'})){
            if(Test-Path -LiteralPath $file.path -PathType Leaf){Assert-Leaf $file.path 'Bucket identity';$binding[$file.key]=(Get-FileHash -LiteralPath $file.path -Algorithm SHA256).Hash.ToLowerInvariant()}
        }
        if(Test-Path -LiteralPath $config -PathType Leaf){
            $remote=[regex]::Match([IO.File]::ReadAllText($config),'(?m)^\s*url\s*=\s*(https://[^\s]+)\s*$')
            if($remote.Success){
                $uri=$null
                if([Uri]::TryCreate($remote.Groups[1].Value,[UriKind]::Absolute,[ref]$uri)){$safe=[UriBuilder]::new($uri);$safe.UserName='';$safe.Password='';$safe.Query='';$safe.Fragment='';$binding['url']=$safe.Uri.AbsoluteUri}
            }
        }elseif($bucket -ceq 'main'){$binding['url']='https://github.com/ScoopInstaller/Main'}
        if(Test-Path -LiteralPath $head -PathType Leaf){
            $reference=([IO.File]::ReadAllText($head)).Trim()
            if($reference -match '^ref: (refs/[A-Za-z0-9/._-]+)$'){
                $refPath=Join-Path (Split-Path -Parent $head) $Matches[1]
                if(Test-Path -LiteralPath $refPath -PathType Leaf){Assert-Leaf $refPath 'Bucket commit';$binding['headSHA256']=(Get-FileHash -LiteralPath $refPath -Algorithm SHA256).Hash.ToLowerInvariant()}
            }
        }
        $sourceBindings+=,$binding
    }
    $facts = [ordered]@{sourceBindings=@($sourceBindings);sharedNamespace=@($sharedNamespace);stopOnFailure=[bool]$request.stopOnFailure;sourceChange=$sourceChange;intent=$intent;root=$root;cache=$cache;architecture=$script:architecture;policy=$script:policy;allowAdmin=[bool](Property $request 'allowAdmin');owner=$owner;bootstrapLock=$lock;zsetup=[ordered]@{version='0.6.5';sha256='07d99ebcaae8739e95d92a510891dd729f7f9da52f898bb19a4360fe6f01ac06'};inventory=$boundInventory;items=@($items);source=[string](Property $request 'source');url=[string](Property $request 'url');elevated=(Market-Elevated)}
    $fingerprint = Market-Hash (Market-Json $facts)
    $risks=@();if($sourceChange -and $intent -ne 'cache-clean'){$risks+='Source changes affect future catalog and script trust. Review URL, commit and installed packages.'};if ($facts.elevated) {$risks+='The current process has an administrator token; user-scope bootstrap requires explicit permission.'};if (@($items | Where-Object {$_.scripts.Count -gt 0}).Count) {$risks+='Manifest scripts execute as the current user. Review their content before confirming.'}
    return [ordered]@{status='planned';fingerprint=$fingerprint;facts=$facts;risks=@($risks);route=@($(if($intent -eq 'setup'){@('kspeeder:task-runtime','zsetup:scoop')}elseif($intent -in @('install','update')){@('ks-cli:scoop')}elseif($intent -in @('refresh','source-add')){@('ks-cli:scoop-bucket-fetch')}else{@('native-scoop-provider')}));bootstrapRequired=($intent -in @('setup','install','update') -and !(Market-CompatibleOwner))}
}
function Market-PrepareTools {
    $directory=[string]$request.toolsRoot
    if (!$directory -or ![IO.Path]::IsPathRooted($directory)) { throw 'An application-owned tool directory is required.' }
    # Reuse the canonical first-dependency owner, with HTTPS-only unattended behavior.
    . (Join-Path $PSScriptRoot '../resources/runtime/kai-tool-bootstrap/resources/bootstrap-windows.ps1')
    $env:ZSETUP_ROOT=$directory
    $zsetup=Get-ZsetupBootstrap
    $expected='07d99ebcaae8739e95d92a510891dd729f7f9da52f898bb19a4360fe6f01ac06'
    if (!(Test-BootstrapBinary $zsetup '0.6.5' $expected)) {throw 'The supported zsetup 0.6.5 identity was not prepared. Re-plan against an updated tool contract.'}
    $runtime=Join-Path $directory $lock.runtime_bundle_id
    $archive=Join-Path $directory 'runtime.zip'
    $provided=[string](Property $request 'runtimeBundlePath')
    if ($provided -and (Test-Path -LiteralPath $provided -PathType Leaf)) {
        Assert-Leaf $provided 'Application runtime bundle'
        if ((Get-Item -LiteralPath $provided).Length -ne $lock.runtime_bundle_size -or (Get-FileHash -LiteralPath $provided -Algorithm SHA256).Hash -ine $lock.runtime_bundle_sha256) {throw 'Application runtime bundle does not match the approved lock'}
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        if ($provided -cne $archive) {Copy-Item -LiteralPath $provided -Destination $archive -Force}
    }
    if (!(Test-Path -LiteralPath $archive) -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $lock.runtime_bundle_sha256) {
        $download=Invoke-NativeCaptured $zsetup @('download','-o',$archive,'--sha256',[string]$lock.runtime_bundle_sha256,'--size',[string]$lock.runtime_bundle_size,('https://dl.istoreos.com/binary/kspeeder/runtimes/'+$lock.runtime_bundle_id+'/runtime.zip'),('https://fw.d4ctech.com/binary/kspeeder/runtimes/'+$lock.runtime_bundle_id+'/runtime.zip'),('https://fw20.koolcenter.com/binary/kspeeder/runtimes/'+$lock.runtime_bundle_id+'/runtime.zip'),'--fallback-url',('https://fw.koolcenter.com/binary/kspeeder/runtimes/'+$lock.runtime_bundle_id+'/runtime.zip'))
        if ($download.exitCode -ne 0) {Fail $download.exitCode 'dependency-download-failed' 'The locked runtime is unavailable from its formal sources.' @{exitCode=$download.exitCode;output=($download.output -join "`n")}}
    }
    if ((Get-Item -LiteralPath $archive).Length -ne $lock.runtime_bundle_size -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $lock.runtime_bundle_sha256) {throw 'Runtime archive identity mismatch'}
    if (!(Test-Path -LiteralPath (Join-Path $runtime 'manifest.json'))) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip=[IO.Compression.ZipFile]::OpenRead($archive)
        try { if ($zip.Entries.Count -ne 4) {throw 'Runtime archive count mismatch'}; foreach ($entry in $zip.Entries) {if (@('identity.json','ks-cli.exe','kspeeder.exe','manifest.json') -cnotcontains $entry.FullName) {throw 'Unsafe runtime archive entry'}} } finally {$zip.Dispose()}
        if (Test-Path -LiteralPath $runtime) {Remove-Item -LiteralPath $runtime -Recurse -Force}
        [IO.Compression.ZipFile]::ExtractToDirectory($archive,$runtime)
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $trustedZip=[IO.Compression.ZipFile]::OpenRead($archive)
    try {$reader=[IO.StreamReader]::new($trustedZip.GetEntry('manifest.json').Open());try {$meta=$reader.ReadToEnd() | ConvertFrom-Json} finally {$reader.Dispose()}} finally {$trustedZip.Dispose()}

    if ($meta.bundle_id -cne $lock.runtime_bundle_id -or $meta.files.Count -ne 3) {throw 'Runtime bundle identity mismatch'}
    foreach ($record in $meta.files) {if (@('identity.json','ks-cli.exe','kspeeder.exe') -cnotcontains $record.path) {throw 'Unsafe runtime manifest path'};$file=Join-Path $runtime $record.path;if ((Get-Item -LiteralPath $file).Length -ne $record.size -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $record.sha256) {throw 'Runtime file checksum mismatch'}}
    $request | Add-Member -Force -NotePropertyName zsetup -NotePropertyValue $zsetup
    $request | Add-Member -Force -NotePropertyName ksCli -NotePropertyValue (Join-Path $runtime 'ks-cli.exe')
    $request | Add-Member -Force -NotePropertyName runtimeBinary -NotePropertyValue (Join-Path $runtime 'kspeeder.exe')
    $request | Add-Member -Force -NotePropertyName runtimeIdentity -NotePropertyValue (Join-Path $runtime 'identity.json')
    return [ordered]@{zsetupVersion='0.6.5';zsetupSHA256=$expected;runtimeBundleId=$lock.runtime_bundle_id;runtimeBundleSHA256=$lock.runtime_bundle_sha256;mode='task-scoped'}
}
function Market-ApplySetup($Plan) {
    Market-Stage 'applying'
    if ($Plan.facts.elevated -and !$Plan.facts.allowAdmin) {throw 'Administrator invocation was not approved. Run KAIPlus as a normal user or explicitly approve the administrator token.'}
    $tools=Market-PrepareTools
    $ownerLock=Market-ReadJson (Join-Path $PSScriptRoot '..\resources\scoop-owner.lock.json')
    $entry=Join-Path $PSScriptRoot ('..\resources\'+$ownerLock.path)
    Assert-Leaf $entry 'Formal Scoop owner entry'
    if ((Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash -ine $ownerLock.sha256) {throw 'Formal Scoop owner source lock mismatch'}
    $hostPS=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args=@('run','--',$hostPS,'-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$entry,'--installer-scope','user','--installer-root',$root,'--installer-cache',$Plan.facts.cache,'--installer-runtime-bundle',(Join-Path ([string]$request.toolsRoot) 'runtime.zip'))
    if ($Plan.facts.allowAdmin) {$args+='--installer-allow-admin'}
    $env:ZSETUP_BIN=[string]$request.zsetup
    $client=[string]$request.ksCli
    $native=Invoke-NativeCaptured $client (@('--json','runtime','exec','--service-binary',[string]$request.runtimeBinary,'--identity',[string]$request.runtimeIdentity,'--require-capability','download-gateway.v1','--require-capability','route.github-archive.v1','--',[string]$request.zsetup)+$args)
    if ($native.exitCode -ne 0) {Fail $native.exitCode 'scoop-bootstrap-failed' 'Formal zsetup Scoop setup failed.' @{exitCode=$native.exitCode;output=($native.output -join "`n")}}
    if (!(Market-CoreOwner $lock)) {throw 'Formal zsetup returned without the exact owner receipt.'}
    $runtimeReceipts=@(Json-Objects ($native.output -join "`n") | Where-Object {(Property $_ 'ephemeral') -eq $true})
    if ($runtimeReceipts.Count -eq 0 -or $runtimeReceipts[-1].status -cne 'passed' -or $runtimeReceipts[-1].cleanup -cne 'complete') {throw 'Runtime lifecycle receipt is incomplete.'}
    return [ordered]@{schemaVersion=1;status='passed';operation='setup';postconditions=@{nativeReconciled=$true};tools=$tools;owner=(Market-ReadJson (Join-Path $root '.linkease-scoop-receipt.json'));runtime=$runtimeReceipts[-1];inventory=(Market-Inventory $root)}
}
function Invoke-Market {
    if ($action -eq 'probe') {Market-Capability;return}
    $script:root=Market-SafeRoot $root
    $env:KAI_SOFTWARE_TASK_RUNTIME_ONLY='1'
    switch ($action) {
        'catalog' {Market-Catalog;return}
        'inventory' {Emit (Market-Inventory $root);return}
        'recovery' {
            $candidates=@();$original=@($request.packages)
            foreach($id in $original){
                try{$request.packages=@($id);$candidate=Market-EmptyInstallPlan;$candidates+=@{packageId=$id;directories=@($candidate.facts.emptyInstall.directories);action='repair-empty-install'}}catch{}
            }
            $request.packages=$original;Emit @{status='ready';candidates=@($candidates);scope='approved-package-closure'};return
        }
        'plan' {Emit (Market-Plan);return}
        'apply' {
            $env:KAI_SOFTWARE_TASK_RUNTIME_ONLY='1'
            $preflight=Market-Plan
            if($preflight.facts.elevated -and !$preflight.facts.allowAdmin){throw 'Administrator token was not approved for this user-scope operation'}
            if ($preflight.fingerprint -cne [string]$request.expectedFingerprint) {Fail 11 'needs-replan' 'Device, source, settings or inventory changed after confirmation.'}
            New-Item -ItemType Directory -Path (Split-Path -Parent $root) -Force | Out-Null
            $marketLock=[IO.File]::Open(($root+'.market.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
            try {
            $current=Market-Plan
            if ($current.fingerprint -cne [string]$request.expectedFingerprint) {Fail 11 'needs-replan' 'Device, source, settings or inventory changed after confirmation.'}
            if ($request.intent -eq 'repair-empty-install') {Emit (Market-ApplyEmptyInstall $current);return}
            if ($request.intent -eq 'setup') {Emit (Market-ApplySetup $current);return}
            if($request.intent -in @('install','update','remove','hold','unhold')){Emit (Market-ApplyPackages $current);return}
            Emit (Market-ApplyMaintenance $current);return
            } finally {$marketLock.Dispose()}
        }
    }
}

function Market-VisitItem([string]$ID){
    if($script:marketVisited[$ID] -eq 2){return};if($script:marketVisited[$ID] -eq 1){throw ('Dependency cycle: '+$ID)}
    $script:marketVisited[$ID]=1;$item=$script:marketItemByID[$ID]
    foreach($dependency in @($item.dependencies)){if(!$dependency){continue};$dep=[string]$dependency;if(!$dep.Contains('/')){$dep='main/'+$dep};$dep='scoop:'+$dep;if($script:marketItemByID.ContainsKey($dep)){Market-VisitItem $dep}}
    $script:marketVisited[$ID]=2;$script:marketOrdered+=,$item
}
function Market-OrderItems($Items){
    $script:marketItemByID=@{};$script:marketVisited=@{};$script:marketOrdered=@()
    foreach($item in @($Items)){$script:marketItemByID[$item.packageId]=$item}
    foreach($item in @($Items)){Market-VisitItem $item.packageId}
    return @($script:marketOrdered)
}

function Market-InstalledManifestPath([string]$Directory){foreach($name in @('scoop-manifest.json','manifest.json')){$path=Join-Path $Directory $name;if(Test-Path -LiteralPath $path -PathType Leaf){Assert-Leaf $path 'Installed manifest';return $path}};throw 'Installed manifest is unresolved'}

function Market-CompatibleOwner {if(!(Market-KnownOwner)){return $false};$receipt=Market-ReadJson (Join-Path $root '.linkease-scoop-receipt.json');return $receipt.core_commit -ceq $lock.core_commit -and $receipt.core_sha256 -ceq $lock.core_sha256}

# Resolution verifies already prepared files only: no extraction, download or
# bootstrap may occur before source-change confirmation.
function Market-ReadOnlyTools {
    $directory=[string]$request.toolsRoot;if(!$directory){throw 'Prepare the controlled software tools before resolving a source'}
    $archive=Join-Path $directory 'runtime.zip';Assert-Leaf $archive 'Prepared runtime archive'
    if((Get-Item -LiteralPath $archive).Length -ne $lock.runtime_bundle_size -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $lock.runtime_bundle_sha256){throw 'Prepared tools need a separately confirmed repair before source resolution'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    try{$reader=[IO.StreamReader]::new($zip.GetEntry('manifest.json').Open());try{$meta=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}}finally{$zip.Dispose()}
    if($meta.bundle_id -cne $lock.runtime_bundle_id -or $meta.files.Count -ne 3){throw 'Prepared runtime identity is invalid'}
    $runtime=Join-Path $directory $lock.runtime_bundle_id
    foreach($record in $meta.files){if(@('identity.json','ks-cli.exe','kspeeder.exe') -cnotcontains $record.path){throw 'Unexpected prepared tool path'};$file=Join-Path $runtime $record.path;Assert-Leaf $file 'Prepared tool';if((Get-Item -LiteralPath $file).Length -ne $record.size -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $record.sha256){throw 'Prepared tool integrity failed'}}
    return @{client=(Join-Path $runtime 'ks-cli.exe');service=(Join-Path $runtime 'kspeeder.exe');identity=(Join-Path $runtime 'identity.json')}
}

# Reserved names model the shared Scoop namespaces, independently of display
# names. Inspect every architecture conservatively for installed packages.
function Market-Namespaces($Manifest){
    $result=@()
    $variants=@($Manifest);$architectures=Property $Manifest 'architecture'
    if($architectures){foreach($property in $architectures.PSObject.Properties){$variants+=,$property.Value}}
    foreach($variant in $variants){
        foreach($entry in @(Property $variant 'bin')){
            if(!$entry){continue};$parts=@($entry);$name=if($parts.Count -gt 1){[string]$parts[1]}else{[IO.Path]::GetFileNameWithoutExtension([string]$parts[0])}
            if($name){$result+=('bin:'+$name.ToLowerInvariant())}
        }
        foreach($entry in @(Property $variant 'shortcuts')){$parts=@($entry);if($parts.Count -gt 1){$result+=('shortcut:'+([string]$parts[1]).ToLowerInvariant())}}
        $environment=Property $variant 'env_set';if($environment){foreach($property in $environment.PSObject.Properties){$result+=('env:'+ $property.Name.ToLowerInvariant())}}
    }
    return @($result|Sort-Object -Unique)
}
