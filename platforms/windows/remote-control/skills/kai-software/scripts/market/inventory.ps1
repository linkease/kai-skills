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
