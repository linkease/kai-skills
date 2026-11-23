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
