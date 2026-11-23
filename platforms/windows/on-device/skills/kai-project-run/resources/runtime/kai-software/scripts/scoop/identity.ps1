function Scoop-Root {
    $root = [Environment]::ExpandEnvironmentVariables([string]$request.root)
    if (!$root) { $root = $env:SCOOP }
    if (!$root) {
        $config = Join-Path $env:USERPROFILE '.config\scoop\config.json'
        if (Test-Path -LiteralPath $config -PathType Leaf) {
            try { $root = [string](Property (Get-Content -LiteralPath $config -Raw | ConvertFrom-Json) 'root_path') } catch {}
        }
    }
    if (!$root) { $root = Join-Path $env:USERPROFILE 'scoop' }
    if (![IO.Path]::IsPathRooted($root)) { Fail 2 'usage' 'Scoop root must be absolute.' }
    return [IO.Path]::GetFullPath($root)
}

function Read-Lock {
    $path = Join-Path $script:SoftwareScriptRoot '..\resources\scoop.lock.json'
    try { $lock = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { Fail 11 'integrity-failed' 'The Scoop ownership lock is unreadable.' }
    if ($lock.schema_version -ne 1 -or $lock.owner -cne 'linkease-zsetup' -or
        [string]$lock.installer_version -cne '0.1.2' -or [string]$lock.core_commit -notmatch '^[0-9a-f]{40}$' -or
        [string]$lock.main_commit -notmatch '^[0-9a-f]{40}$' -or [string]$lock.runtime_bundle_sha256 -notmatch '^[0-9a-f]{64}$') {
        Fail 11 'integrity-failed' 'The Scoop ownership lock has an unsupported identity.'
    }
    return $lock
}

function Test-OwnedScoop([string]$Root, $Lock) {
    $receiptPath = Join-Path $Root '.linkease-scoop-receipt.json'
    if (!(Test-Path -LiteralPath $receiptPath -PathType Leaf)) { return $false }
    try { $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json } catch { return $false }
    if ($receipt.schema_version -ne 1 -or [string]$receipt.owner -cne [string]$Lock.owner -or
        [string]$receipt.installer_version -cne [string]$Lock.installer_version -or
        [string]$receipt.runtime_bundle_id -cne [string]$Lock.runtime_bundle_id -or
        [string]$receipt.runtime_bundle_sha256 -cne [string]$Lock.runtime_bundle_sha256 -or
        [string]$receipt.core_commit -cne [string]$Lock.core_commit -or
        [string]$receipt.core_sha256 -cne [string]$Lock.core_sha256 -or
        [string]$receipt.main_commit -cne [string]$Lock.main_commit -or
        [string]$receipt.main_sha256 -cne [string]$Lock.main_sha256) { return $false }
    foreach ($relative in @('apps\scoop\current\bin\scoop.ps1','buckets\main\bucket\7zip.json','shims\scoop.cmd')) {
        if (!(Test-Path -LiteralPath (Join-Path $Root $relative) -PathType Leaf)) { return $false }
    }
    return $true
}

function Ensure-OwnedScoop([string]$Root, $Lock) {
    if (Test-OwnedScoop $Root $Lock) { return $false }
    $zsetup = [string]$request.zsetup
    if (!$zsetup) { $zsetup = $env:KAI_ZSETUP_BIN }
    Assert-Leaf $zsetup 'zsetup'
    $native = Invoke-NativeCaptured $zsetup @('install','scoop','--foreground','--','--installer-scope','user','--installer-root',$Root,'--installer-cache',(Join-Path $Root 'cache'))
    if ($native.exitCode -ne 0) { Fail $native.exitCode 'scoop-bootstrap-failed' 'The formal zsetup Scoop application failed.' @{exitCode=$native.exitCode;output=($native.output -join "`n")} }
    if (!(Test-OwnedScoop $Root $Lock)) { Fail 11 'invalid-provider-receipt' 'zsetup returned success without the exact locked M6 Scoop receipt and files.' }
    return $true
}

function Parse-Identity([string]$Identity, [switch]$BucketOnly) {
    if ($BucketOnly) {
        if ($Identity -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { Fail 2 'usage' 'Use scoop:BUCKET for refresh.' }
        return @($Identity, '')
    }
    if ($Identity -notmatch '^([A-Za-z0-9][A-Za-z0-9._-]*)/([A-Za-z0-9][A-Za-z0-9._-]*)$') {
        Fail 2 'usage' 'Use scoop:BUCKET/APP.'
    }
    return @($Matches[1], $Matches[2])
}

function Manifest([string]$Root, [string]$Bucket, [string]$App) {
    $path = Join-Path $Root ("buckets\$Bucket\bucket\$App.json")
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { Fail 4 'no-candidate' 'The exact Scoop bucket does not contain this application.' }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { Fail 11 'catalog-unavailable' 'The selected Scoop manifest is invalid.' }
}

function Bin-Records($Manifest) {
    $value = Effective $Manifest 'bin'
    $records = @()
    if ($null -eq $value) { return @() }
    if ($value -is [string]) { $value = @($value) }
    foreach ($entry in @($value)) {
        if ($entry -is [string]) { $target = [string]$entry; $alias = [IO.Path]::GetFileNameWithoutExtension($target) }
        else {
            $parts = @($entry)
            if ($parts.Count -eq 0) { continue }
            $target = [string]$parts[0]
            $alias = [IO.Path]::GetFileNameWithoutExtension($target)
            if ($parts.Count -gt 1 -and ![string]::IsNullOrWhiteSpace([string]$parts[1])) { $alias = [IO.Path]::GetFileNameWithoutExtension([string]$parts[1]) }
        }
        if ($target -and $alias) { $records += [pscustomobject]@{target=$target;alias=$alias} }
    }
    return @($records)
}

function Scoop-Info([string]$Root, [string]$Bucket, [string]$App) {
    $manifest = Manifest $Root $Bucket $App
    $version = [string](Property $manifest 'version')
    if (!$version) { Fail 11 'catalog-unavailable' 'The selected Scoop manifest has no version.' }
    $versionRoot = Join-Path $Root ("apps\$App\$version")
    $installed = Test-Path -LiteralPath $versionRoot -PathType Container
    $shortcuts = @(Effective $manifest 'shortcuts')
    $type = 'cli-tool'
    if ($shortcuts.Count -gt 0 -and $null -ne $shortcuts[0]) { $type = 'desktop-app' }
    $entrypoint = ''
    foreach ($bin in @(Bin-Records $manifest)) {
        foreach ($extension in @('.exe','.cmd','.ps1','')) {
            $candidate = Join-Path $Root ('shims\' + $bin.alias + $extension)
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $entrypoint = $candidate; break }
        }
        if ($entrypoint) { break }
    }
    $description = [string](Property $manifest 'description')
    return [ordered]@{schemaVersion=1;id=("scoop:$Bucket/$App");name=$App;displayName=$App;
        description=$description;type=$type;source='scoop';manager='scoop';platform='windows';compatible=$true;
        availableVersion=$version;installedVersion=$(if ($installed) {$version} else {''});installed=$installed;
        entrypoint=$entrypoint;evidenceTime=[DateTime]::UtcNow.ToString('o')}
}

function Resolve-Architecture {
    $value = [string]$request.architecture
    if (!$value) { $value = $env:KAI_WINGET_ARCH }
    if (!$value) { $value = $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ($value) {
        '^(?i:x64|amd64|64bit)$' { return '64bit' }
        '^(?i:x86|32bit)$' { return '32bit' }
        '^(?i:arm64)$' { return 'arm64' }
        default { Fail 2 'usage' 'Select x64, x86 or arm64 for Scoop.' }
    }
}
