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
