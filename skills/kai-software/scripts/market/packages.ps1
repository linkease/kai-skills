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
    $supported=Market-ReadJson (Join-Path $script:SoftwareScriptRoot '..\resources\supported-scoop-owners.json')
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
