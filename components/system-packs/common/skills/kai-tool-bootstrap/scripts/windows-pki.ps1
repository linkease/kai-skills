#requires -Version 7.4
param(
    [ValidateSet('Roots','Check','Plan','Repair','Restore')][string]$Action = 'Plan',
    [string]$Bundle,
    [string]$StateDirectory,
    [ValidateRange(0,2592000)][int]$MinimumValiditySeconds = 300
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$lock = $null; $lockPath = $null; $state = $null; $statePath = $null
$beforeOwned = @{}; $mutationStarted = $false
function Assert-PlainPath([string]$Path) {
    if (-not [IO.Path]::IsPathFullyQualified($Path)) { throw 'An absolute path is required' }
    $item = [IO.Path]::GetFullPath($Path)
    while ($item) {
        if (Test-Path -LiteralPath $item) {
            if ((Get-Item -Force -LiteralPath $item).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse paths are not supported' }
        }
        $parent = [IO.Path]::GetDirectoryName($item)
        if ($parent -eq $item) { break }; $item = $parent
    }
}
function Read-Json([string]$Path) {
    Assert-PlainPath $Path
    $file = Get-Item -LiteralPath $Path
    if ($file.Length -gt 4194304) { throw 'JSON input exceeds 4 MiB' }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
}
function Save-State {
    $temporary = $statePath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($state | ConvertTo-Json -Depth 12 -Compress))
        $file=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $file.Write($bytes,0,$bytes.Length); $file.Flush($true) } finally { $file.Dispose() }
        [IO.File]::Move($temporary, $statePath, $true)
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}
function Result($Value) { $Value | ConvertTo-Json -Depth 10 -Compress }
try {
    if (-not $IsWindows) { throw 'Native Windows is required' }
    $native = Join-Path $PSScriptRoot '../resources/windows-pki.cs'
    Assert-PlainPath ([IO.Path]::GetFullPath($native))
    Add-Type -Path $native -IgnoreWarnings -WarningAction SilentlyContinue
    if ($Action -eq 'Roots') {
        Result @{ schemaVersion=1; roots=@([KaiWindowsPki]::GetRoots() | ForEach-Object { [Convert]::ToBase64String($_) }) }
        exit 0
    }
    $rootBefore = [KaiWindowsPki]::RootDigest()
    $validation = $null; $document = $null
    if ($Action -ne 'Restore') {
        $document = Read-Json $Bundle
        if ($document.schemaVersion -ne 1) { throw 'Unsupported PKI bundle schema' }
        if (@($document.leaves).Count -eq 0 -or @($document.leaves).Count -gt 16 -or @($document.certificates).Count -gt 64 -or @($document.crls).Count -gt 64) { throw 'Invalid PKI bundle counts' }
        $hosts = [string[]]@($document.leaves | ForEach-Object { $_.host })
        $leaves = [byte[][]]@($document.leaves | ForEach-Object { ,[Convert]::FromBase64String($_.der) })
        if ($Action -eq 'Check') {
            [void][KaiWindowsPki]::CheckStores($hosts,$leaves)
            if ([KaiWindowsPki]::RootDigest() -cne $rootBefore) { throw 'Root store changed during Check' }
            Result @{schemaVersion=1;status='healthy';hosts=$hosts;validationScope='current-user-capi-chain';nativeDownloaderValidated=$false;systemProxyChanged=$false;rootStoreChanged=$false}
            exit 0
        }
        $certs = [byte[][]]@($document.certificates | ForEach-Object { ,[Convert]::FromBase64String($_.der) })
        $crls = [byte[][]]@($document.crls | ForEach-Object { ,[Convert]::FromBase64String($_.der) })
        $validation = [KaiWindowsPki]::Validate($hosts, $leaves, $certs, $crls)
        if ([DateTime]::Parse($validation.ValidUntilUtc).ToUniversalTime() -le [DateTime]::UtcNow.AddSeconds($MinimumValiditySeconds)) { throw 'PKI material has insufficient remaining validity; fetch fresh material' }
        if ([KaiWindowsPki]::RootDigest() -cne $rootBefore) { throw 'Root store changed during validation' }
        if ($Action -eq 'Plan') {
            $present = @{}; foreach ($item in [KaiWindowsPki]::Snapshot()) { $present[$item.Kind+':'+$item.Sha256] = $true }
            Result @{ schemaVersion=1; status='ready'; hosts=$hosts; validUntilUtc=$validation.ValidUntilUtc
                materials=@($validation.Materials | ForEach-Object { @{ kind=$_.Kind; sha256=$_.Sha256; present=$present.ContainsKey($_.Kind+':'+$_.Sha256); expiresUtc=$_.ExpiresUtc } })
                destination='CurrentUser\CA'; validationScope='current-user-capi-chain'; nativeDownloaderValidated=$false; systemProxyChanged=$false; rootStoreChanged=$false }
            exit 0
        }
    }
    Assert-PlainPath $StateDirectory
    $StateDirectory = [IO.Path]::GetFullPath($StateDirectory)
    $statePath = Join-Path $StateDirectory 'state.json'
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($Action -eq 'Restore' -and -not (Test-Path -LiteralPath $statePath)) {
        Result @{ schemaVersion=1; status='restored'; removed=0; absent=0; systemProxyChanged=$false; rootStoreChanged=$false }; exit 0
    }
    if (-not (Test-Path -LiteralPath $StateDirectory)) { [void][IO.Directory]::CreateDirectory($StateDirectory) }
    if (-not (Test-Path -LiteralPath $statePath) -and @(Get-ChildItem -Force -LiteralPath $StateDirectory | Where-Object { $_.Name -ne '.lock' }).Count) { throw 'State directory contains unowned files' }
    $lockPath = Join-Path $StateDirectory '.lock'
    Assert-PlainPath $lockPath
    $lockExisted=Test-Path -LiteralPath $lockPath
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $marker=[Text.Encoding]::ASCII.GetBytes('kai-windows-pki-lock-v1')
    if ($lock.Length -eq 0) {
        if ($lockExisted) {
            if (-not (Test-Path -LiteralPath $statePath)) { throw 'Unowned lock file preserved' }
            $prior=Read-Json $statePath
            if ($prior.schemaVersion -ne 1 -or $prior.scope -cne 'CurrentUser\CA' -or $prior.sid -cne $sid) { throw 'Unowned lock file preserved' }
        }
        $lock.Write($marker,0,$marker.Length); $lock.Flush($true)
    } elseif ($lock.Length -eq $marker.Length) {
        $actual=[byte[]]::new($marker.Length); [void]$lock.Read($actual,0,$actual.Length)
        if ([Convert]::ToBase64String($actual) -cne [Convert]::ToBase64String($marker)) { throw 'Unowned lock file preserved' }
    } else { throw 'Unowned lock file preserved' }
    if (Test-Path -LiteralPath $statePath) {
        $state = Read-Json $statePath
        if ($state.schemaVersion -ne 1 -or $state.scope -cne 'CurrentUser\CA' -or $state.sid -cne $sid) { throw 'Conflicting PKI state' }
        $id = [Guid]::Empty; if (-not [Guid]::TryParse($state.owner, [ref]$id)) { throw 'Invalid ownership state' }
    } else {
        if (@(Get-ChildItem -Force -LiteralPath $StateDirectory | Where-Object { $_.Name -ne '.lock' }).Count) { throw 'State directory contains unowned files' }
        $state = @{ schemaVersion=1; scope='CurrentUser\CA'; sid=$sid; owner=[Guid]::NewGuid().ToString(); status='prepared'; objects=@() }
        Save-State
    }
    $current=@([KaiWindowsPki]::Snapshot())
    foreach ($item in @($state.objects)) {
        if ($item.state -in @('owned','intent','conflict')) {
            $matches=@($current | Where-Object { $_.Kind -ceq $item.kind -and $_.Sha256 -ceq $item.sha256 })
            if ($matches.Count -and -not @($matches | Where-Object { $_.Owner -ceq $state.owner }).Count) { throw 'Ownership conflict preserved' }
        }
    }
    if ($Action -eq 'Restore') {
        $removed=0; $absent=0; $conflicts=0
        $expected=@{}
        foreach ($item in @($state.objects)) {
            if ($item.kind -notin @('certificate','crl') -or $item.sha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid object journal' }
            $key=$item.kind+':'+$item.sha256
            if ($expected.ContainsKey($key)) { throw 'Duplicate object journal' }; $expected[$key]=$true
        }
        foreach ($item in [KaiWindowsPki]::Snapshot()) {
            if ($item.Owner -ceq $state.owner -and -not $expected.ContainsKey($item.Kind+':'+$item.Sha256)) { throw 'Unrecognized owned object preserved during Restore' }
        }
        foreach ($item in @($state.objects)) {
            if ($item.state -eq 'reused') { continue }
            $outcome = [KaiWindowsPki]::RemoveOwned($item.kind, $item.sha256, $state.owner)
            if ($outcome -eq 'conflict') { $item.state='conflict'; $conflicts++ }
            else { $item.state='restored'; if ($outcome -eq 'removed') { $removed++ } else { $absent++ } }
            Save-State
        }
        if ($conflicts) { throw 'Ownership conflicts preserved during Restore' }
        $state.status='restored'; Save-State
        if ([KaiWindowsPki]::RootDigest() -cne $rootBefore) { throw 'Root store changed during Restore' }
        Result @{ schemaVersion=1; status='restored'; removed=$removed; absent=$absent; systemProxyChanged=$false; rootStoreChanged=$false }
        exit 0
    }
    foreach ($item in [KaiWindowsPki]::Snapshot()) { if ($item.Owner -ceq $state.owner) { $beforeOwned[$item.Kind+':'+$item.Sha256]=$true } }
    $mutationStarted=$true; $added=0; $reused=0
    foreach ($material in $validation.Materials) {
        $entry = @($state.objects | Where-Object { $_.kind -ceq $material.Kind -and $_.sha256 -ceq $material.Sha256 })
        if ($entry.Count -gt 1) { throw 'Duplicate object journal' }
        if (-not $entry.Count) {
            $record=@{ kind=$material.Kind; sha256=$material.Sha256; state='intent' }
            $state.objects += $record
        } else { $record=$entry[0]; $record.state='intent' }
        $state.status='repairing'; Save-State
        if ([KaiWindowsPki]::Add($material, $state.owner)) { $added++ } else { $reused++ }
        $owned=@([KaiWindowsPki]::Snapshot() | Where-Object { $_.Kind -ceq $material.Kind -and $_.Sha256 -ceq $material.Sha256 -and $_.Owner -ceq $state.owner })
        $record.state=if ($owned.Count) { 'owned' } else { 'reused' }; Save-State
    }
    if ([KaiWindowsPki]::RootDigest() -cne $rootBefore) { throw 'Root store changed during Repair' }
    $state.status='active'; $state.validUntilUtc=$validation.ValidUntilUtc; Save-State
    Result @{ schemaVersion=1; status='repaired'; added=$added; reused=$reused; validUntilUtc=$validation.ValidUntilUtc
        validationScope='current-user-capi-chain'; nativeDownloaderValidated=$false; systemProxyChanged=$false; rootStoreChanged=$false }
    exit 0
} catch {
    $message=$_.Exception.Message
    if ($mutationStarted -and $state) {
        try {
            foreach ($item in $state.objects) {
                if (-not $beforeOwned.ContainsKey($item.kind+':'+$item.sha256) -and $item.state -ne 'reused') {
                    $outcome=[KaiWindowsPki]::RemoveOwned($item.kind,$item.sha256,$state.owner)
                    $item.state=if ($outcome -eq 'conflict') { 'conflict' } else { 'restored' }
                }
            }
            $state.status='failed'; Save-State
        } catch { $message += '; rollback incomplete: ' + $_.Exception.Message }
    }
    Result @{ schemaVersion=1; status='failed'; category='pki-repair-unavailable'; message=$message; systemProxyChanged=$false }
    exit 11
} finally {
    # Keep the owned marker; closing the handle releases the exclusive lock.
    # Unlinking by path after close could remove another process's new file.
    if ($lock) { $lock.Dispose() }
}
