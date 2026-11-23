function Market-PrepareTools {
    $directory=[string]$request.toolsRoot
    if (!$directory -or ![IO.Path]::IsPathRooted($directory)) { throw 'An application-owned tool directory is required.' }
    # Reuse the canonical first-dependency owner, with HTTPS-only unattended behavior.
    . $script:SoftwareBootstrapScript
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
    $ownerLock=Market-ReadJson (Join-Path $script:SoftwareScriptRoot '..\resources\scoop-owner.lock.json')
    $entry=Join-Path $script:SoftwareScriptRoot ('..\resources\'+$ownerLock.path)
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
