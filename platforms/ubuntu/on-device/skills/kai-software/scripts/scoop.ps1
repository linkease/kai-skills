# PowerShell 5.1+; pinned zsetup Scoop ownership and ks-cli payload workflow.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

function Emit($Value) {
    [Console]::Out.WriteLine((ConvertTo-Json -InputObject $Value -Depth 12 -Compress))
}
function Json-Objects([string]$Text) {
    $results = @(); $start = -1; $depth = 0; $quoted = $false; $escaped = $false
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        if ($start -lt 0) {
            if ($character -eq '{') { $start = $index; $depth = 1; $quoted = $false; $escaped = $false }
            continue
        }
        if ($quoted) {
            if ($escaped) { $escaped = $false; continue }
            if ($character -eq '\') { $escaped = $true; continue }
            if ($character -eq '"') { $quoted = $false }
            continue
        }
        if ($character -eq '"') { $quoted = $true; continue }
        if ($character -eq '{') { $depth++ }
        if ($character -eq '}') {
            $depth--
            if ($depth -eq 0) {
                try { $results += $Text.Substring($start, $index - $start + 1) | ConvertFrom-Json } catch {}
                $start = -1
            }
        }
    }
    return @($results)
}
function Fail([int]$Code, [string]$Category, [string]$Reason, $NativeResult = $null) {
    Emit ([ordered]@{schemaVersion=1;status='failed';category=$Category;reason=$Reason;
        nativeResult=$NativeResult;exitCode=$Code})
    exit $Code
}
function Property($Value, [string]$Name) {
    if ($null -eq $Value) { return $null }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}
function Effective($Manifest, [string]$Name) {
    $architectures = Property $Manifest 'architecture'
    $branch = Property $architectures $script:architecture
    $value = Property $branch $Name
    if ($null -eq $value) { $value = Property $Manifest $Name }
    return $value
}
function Assert-Leaf([string]$Path, [string]$Label) {
    if (!$Path -or ![IO.Path]::IsPathRooted($Path)) { Fail 2 'usage' "$Label must be an absolute path." }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item -or $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Fail 127 'missing-executable' "$Label must be an existing regular file."
    }
}
function Invoke-NativeCaptured([string]$Executable, [object[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $Executable @Arguments 2>&1)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    return [pscustomobject]@{exitCode=$code;output=@($output)}
}
function Scoop-Root {
    $root = [string]$request.root
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
    $path = Join-Path $PSScriptRoot '..\resources\scoop.lock.json'
    try { $lock = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { Fail 11 'integrity-failed' 'The Scoop ownership lock is unreadable.' }
    if ($lock.schema_version -ne 1 -or $lock.owner -cne 'linkease-zsetup' -or
        [string]$lock.installer_version -cne '0.1.0' -or [string]$lock.core_commit -notmatch '^[0-9a-f]{40}$' -or
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
function KsCli {
    $client = [string]$request.ksCli
    if (!$client) { $client = $env:KAI_KSCLI_BIN }
    Assert-Leaf $client 'ks-cli'
    return $client
}
function Invoke-KsCli([string[]]$Arguments, [string[]]$Capabilities) {
    $client = KsCli
    $runtime = [string]$request.runtimeBinary
    $identity = [string]$request.runtimeIdentity
    if (($runtime -and !$identity) -or ($identity -and !$runtime)) { Fail 2 'usage' 'Runtime binary and identity must be supplied together.' }
    $command = @('--json') + $Arguments
    if ($script:policy -eq 'required' -and $runtime) {
        Assert-Leaf $runtime 'KSpeeder runtime binary'; Assert-Leaf $identity 'KSpeeder runtime identity'
        $wrapper = @('--json','runtime','exec','--service-binary',$runtime,'--identity',$identity)
        foreach ($capability in $Capabilities) { $wrapper += @('--require-capability',$capability) }
        $command = $wrapper + @('--',$client) + $command
    }
    $native = Invoke-NativeCaptured $client $command
    if ($native.exitCode -ne 0) { Fail $native.exitCode 'native-package-failed' 'ks-cli Scoop workflow failed.' @{exitCode=$native.exitCode;output=($native.output -join "`n")} }
    return @($native.output)
}
function Assert-PayloadReceipt($Receipt, [string]$Operation, [string]$Target) {
    if ($Receipt.schema_version -ne 1 -or [string]$Receipt.status -cne 'passed' -or [string]$Receipt.tool -cne 'scoop' -or
        [string]$Receipt.operation -cne $Operation -or [string]$Receipt.target -cne $Target -or
        [string]$Receipt.architecture -cne $script:architecture -or [string]$Receipt.bucket_commit -notmatch '^[0-9a-f]{40}$' -or
        [string]$Receipt.acceleration_policy -cne $script:policy -or $Receipt.native_exit_code -ne 0 -or
        [string]$Receipt.integrity -cne 'manifest-hash-and-native-scoop' -or @($Receipt.packages).Count -lt 1 -or
        $Receipt.system_proxy_changed -ne $false -or $Receipt.global_git_config_changed -ne $false) {
        Fail 11 'invalid-provider-receipt' 'ks-cli returned a mismatched Scoop receipt.' $Receipt
    }
    $targetFound = $false
    foreach ($package in @($Receipt.packages)) {
        if ([string]$package.identity -ceq $Target) { $targetFound = $true }
        if ([string]$package.identity -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$' -or
            [string]::IsNullOrWhiteSpace([string]$package.version) -or @($package.payloads).Count -lt 1) {
            Fail 11 'invalid-provider-receipt' 'A Scoop package receipt is incomplete.' $Receipt
        }
        foreach ($payload in @($package.payloads)) {
            if ([string]::IsNullOrWhiteSpace([string]$payload.id) -or [string]::IsNullOrWhiteSpace([string]$payload.selected) -or
                [long]$payload.bytes -lt 0) {
                Fail 11 'invalid-provider-receipt' 'A Scoop payload receipt is incomplete.' $Receipt
            }
            if ($script:policy -eq 'required' -and
                (!([string]$payload.selected).StartsWith('admin_proxy') -or $payload.hash_verified -ne $true -or $payload.cache_seeded -ne $true)) {
                Fail 11 'invalid-provider-receipt' 'Required Scoop payload acceleration was not proven.' $Receipt
            }
            if ($script:policy -eq 'none' -and
                ([string]$payload.selected -cne 'not-applied' -or [long]$payload.bytes -ne 0 -or
                    $payload.hash_verified -ne $false -or $payload.cache_seeded -ne $false)) {
                Fail 11 'invalid-provider-receipt' 'None policy receipt incorrectly claims a payload transfer.' $Receipt
            }
        }
    }
    if (!$targetFound) { Fail 11 'invalid-provider-receipt' 'The Scoop receipt does not contain the requested package.' $Receipt }
}
function Invoke-Install([string]$Root, [string]$Target, [string]$Version) {
    $parts = Parse-Identity $Target
    $before = Scoop-Info $Root $parts[0] $parts[1]
    if ($Version -and [string]$before.availableVersion -cne $Version) { Fail 4 'version-unavailable' 'Requested exact version differs from the pinned Scoop manifest.' }
    $receiptRoot = Join-Path ([IO.Path]::GetTempPath()) ('kai-scoop-receipt-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $receiptRoot | Out-Null
    $receiptPath = Join-Path $receiptRoot 'receipt.json'
    try {
        $null = Invoke-KsCli @('scoop','install','--architecture',$script:architecture,'--policy',$script:policy,'--receipt',$receiptPath,$Target) @('download-gateway.v1','route.github-release.v1')
        if (!(Test-Path -LiteralPath $receiptPath -PathType Leaf)) { Fail 11 'invalid-provider-receipt' 'ks-cli did not create the requested Scoop receipt.' }
        try { $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json } catch { Fail 11 'invalid-provider-receipt' 'The Scoop receipt is not JSON.' }
        Assert-PayloadReceipt $receipt 'install' $Target
        $result = Scoop-Info $Root $parts[0] $parts[1]
        if (!$result.installed -or [string]$result.installedVersion -cne [string]$result.availableVersion) { Fail 11 'version-mismatch' 'Scoop installation state differs from its manifest.' }
        $result['nativeReceipt'] = $receipt
        Emit $result
    } finally { Remove-Item -LiteralPath $receiptRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
function Invoke-Remove([string]$Root, [string]$Target) {
    $parts = Parse-Identity $Target
    $manifest = Manifest $Root $parts[0] $parts[1]
    $appRoot = Join-Path $Root ('apps\' + $parts[1])
    if (!(Test-Path -LiteralPath $appRoot -PathType Container)) {
        Emit @{schemaVersion=1;status='passed';operation='remove';id=('scoop:'+$Target);reused=$true;exitCode=0}; return
    }
    $xdg = Join-Path ([IO.Path]::GetTempPath()) ('kai-scoop-config-' + [Guid]::NewGuid().ToString('N'))
    $config = Join-Path $xdg 'scoop'; New-Item -ItemType Directory -Path $config | Out-Null
    [IO.File]::WriteAllText((Join-Path $config 'config.json'), '{"no_junction":true,"use_lessmsi":true}', (New-Object Text.UTF8Encoding($false)))
    $previous = $env:XDG_CONFIG_HOME; $env:XDG_CONFIG_HOME = $xdg
    try {
        $native = Invoke-NativeCaptured (Join-Path $Root 'shims\scoop.cmd') @('uninstall',$parts[1])
        if ($native.exitCode -ne 0) { Fail $native.exitCode 'native-package-failed' 'Native Scoop uninstall failed.' @{exitCode=$native.exitCode;output=($native.output -join "`n")} }
    } finally { $env:XDG_CONFIG_HOME = $previous; Remove-Item -LiteralPath $xdg -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $appRoot) { Fail 11 'remove-incomplete' 'Scoop app directory remains after uninstall.' }
    foreach ($bin in @(Bin-Records $manifest)) { foreach ($extension in @('.exe','.cmd','.ps1')) {
        if (Test-Path -LiteralPath (Join-Path $Root ('shims\'+$bin.alias+$extension))) { Fail 11 'remove-incomplete' 'A Scoop shim remains after uninstall.' }
    } }
    Emit @{schemaVersion=1;status='passed';operation='remove';id=('scoop:'+$Target);exitCode=0}
}
function Invoke-Files([string]$Root, [string]$Target) {
    $parts = Parse-Identity $Target; $info = Scoop-Info $Root $parts[0] $parts[1]
    if (!$info.installed) { Fail 4 'not-installed' 'The selected Scoop application is not installed.' }
    $base = Join-Path $Root ("apps\$($parts[1])\$($info.installedVersion)")
    $files = @(); $queue = New-Object Collections.Queue; $queue.Enqueue($base)
    while ($queue.Count -gt 0) {
        $directory = [string]$queue.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            $files += $item.FullName
            if ($item.PSIsContainer -and !($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $queue.Enqueue($item.FullName) }
        }
    }
    Emit @{schemaVersion=1;status='passed';operation='files';id=('scoop:'+$Target);files=@($files);exitCode=0}
}

try {
    $request = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $action = [string]$request.action; $subject = [string]$request.subject; $version = [string]$request.version
    if ($action -notin @('search','info','install','remove','refresh','files')) { Fail 2 'usage' 'Unknown Scoop software operation.' }
    $script:policy = [string]$request.policy; if (!$script:policy) { $script:policy = 'auto' }
    if ($script:policy -notin @('required','auto','none')) { Fail 2 'usage' 'Select required, auto or none.' }
    $script:architecture = Resolve-Architecture
    $root = Scoop-Root; $lock = Read-Lock
    $env:SCOOP = $root; $env:Path = (Join-Path $root 'shims') + [IO.Path]::PathSeparator + $env:Path
    if ($action -eq 'search') {
        if (!$subject -or $subject.StartsWith('-') -or $subject.Length -gt 256) { Fail 2 'usage' 'Supply a bounded literal search term.' }
        if (!(Test-OwnedScoop $root $lock)) { Emit @(); exit 0 }
        $rows = @()
        foreach ($bucketDirectory in @(Get-ChildItem -LiteralPath (Join-Path $root 'buckets') -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
            if ($bucketDirectory.Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { continue }
            $exactName = ''
            if ($subject -match '^[A-Za-z0-9][A-Za-z0-9._-]*$' -and
                (Test-Path -LiteralPath (Join-Path $bucketDirectory.FullName ("bucket\$subject.json")) -PathType Leaf)) {
                $exactName = $subject
                $row = Scoop-Info $root $bucketDirectory.Name $exactName; $row['matchReason'] = 'exact name in the selected Scoop bucket'
                $rows += $row
            }
            foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $bucketDirectory.FullName 'bucket') -File -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object BaseName)) {
                if ($file.BaseName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { continue }
                if ($file.BaseName -ceq $exactName) { continue }
                try { $manifest = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json } catch { continue }
                $haystack = $file.BaseName + ' ' + [string](Property $manifest 'description') + ' ' + [string](Property $manifest 'homepage')
                if ($haystack.IndexOf($subject, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
                $row = Scoop-Info $root $bucketDirectory.Name $file.BaseName; $row['matchReason'] = 'matched in the selected Scoop bucket'
                $rows += $row; if ($rows.Count -ge 5) { break }
            }
            if ($rows.Count -ge 5) { break }
        }
        Emit @($rows); exit 0
    }
    if ($action -eq 'install') { $null = Ensure-OwnedScoop $root $lock; Invoke-Install $root $subject $version; exit 0 }
    if (!(Test-OwnedScoop $root $lock)) { Fail 11 'invalid-provider-receipt' 'Scoop is not owned by the exact locked zsetup M6 installation.' }
    if ($action -eq 'refresh') {
        $parts = Parse-Identity $subject -BucketOnly
        $output = Invoke-KsCli @('scoop','bucket','update','--policy',$script:policy,$parts[0]) @('route.git-github.v1')
        $receipt = $null
        foreach ($candidate in @(Json-Objects ($output -join "`n"))) { if ($candidate.operation -eq 'bucket-update') { $receipt = $candidate } }
        if ($null -eq $receipt -or $receipt.status -ne 'passed' -or $receipt.bucket -cne $parts[0] -or $receipt.acceleration_policy -cne $script:policy -or $receipt.global_git_config_changed -ne $false -or $receipt.remote_url_changed -ne $false) {
            Fail 11 'invalid-provider-receipt' 'ks-cli returned a mismatched bucket update receipt.' $receipt
        }
        Emit @{schemaVersion=1;status='passed';operation='refresh';provider='scoop';bucket=$parts[0];nativeReceipt=$receipt;exitCode=0}; exit 0
    }
    $parts = Parse-Identity $subject
    if ($action -eq 'info') { Emit (Scoop-Info $root $parts[0] $parts[1]); exit 0 }
    if ($action -eq 'files') { Invoke-Files $root $subject; exit 0 }
    if ($action -eq 'remove') { Invoke-Remove $root $subject; exit 0 }
} catch {
    Fail 11 'provider-failed' $_.Exception.Message
}
