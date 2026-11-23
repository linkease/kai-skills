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
