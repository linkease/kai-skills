# Generated from lib/bootstrap.ps1, scoop/business.ps1 and scoop/main.ps1.
$script:ScoopUtf8NoBom = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $script:ScoopUtf8NoBom
[Console]::OutputEncoding = $script:ScoopUtf8NoBom
$OutputEncoding = $script:ScoopUtf8NoBom

# Shared first-dependency bootstrap. Business packages use canonical zsetup.
# Kept separate from business functions and embedded by the entry generator.
$script:BootstrapPrimaryBases = @('https://dl.istoreos.com/binary', 'https://fw.d4ctech.com/binary', 'https://fw20.koolcenter.com/binary')
$script:BootstrapFallbackBase = 'https://fw.koolcenter.com/binary'
if ($env:ZSETUP_BOOTSTRAP_BASES) {
    $script:BootstrapPrimaryBases = @($env:ZSETUP_BOOTSTRAP_BASES -split '\s+' | Where-Object { $_ })
    $script:BootstrapFallbackBase = ''
}
$script:BootstrapInsecureConfirmed = $false
$script:BootstrapArtifact = 'zsetup-windows-i686.exe'

function Get-BootstrapUri([string]$Base, [string]$Path, [string]$Scheme) {
    $uri = [Uri]$Base
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw 'zsetup: bootstrap bases must be HTTPS URLs without credentials, query or fragment'
    }
    $builder = [UriBuilder]::new($uri.AbsoluteUri.TrimEnd('/') + '/' + $Path)
    $builder.Scheme = $Scheme
    if ($uri.IsDefaultPort) { $builder.Port = -1 }
    return $builder.Uri.AbsoluteUri
}

function Initialize-BootstrapTrust {
    if ('LinkeaseBootstrapTrust' -as [type]) { return }
    # A constant delegate runs without a PowerShell runspace on TLS worker threads.
    # Extra roots apply only to this process/request, never to the machine store.
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
using System.Text.RegularExpressions;
public static class LinkeaseBootstrapTrust {
    private static X509Certificate2Collection roots = new X509Certificate2Collection();
    public static readonly RemoteCertificateValidationCallback Callback = Validate;
    public static void Clear() {
        foreach (X509Certificate2 root in roots) root.Dispose();
        roots.Clear();
    }
    public static void Configure(string path) {
        Clear();
        if (new FileInfo(path).Length > 131072) throw new IOException("CA file exceeds bootstrap bound");
        string pem = File.ReadAllText(path);
        foreach (Match m in Regex.Matches(pem, "-----BEGIN CERTIFICATE-----([\\s\\S]*?)-----END CERTIFICATE-----")) {
            roots.Add(new X509Certificate2(Convert.FromBase64String(m.Groups[1].Value)));
        }
        if (roots.Count == 0) throw new IOException("CA file contains no certificate");
    }
    private static bool Validate(object sender, X509Certificate certificate, X509Chain supplied, SslPolicyErrors errors) {
        if (certificate == null || (errors & (SslPolicyErrors.RemoteCertificateNameMismatch | SslPolicyErrors.RemoteCertificateNotAvailable)) != 0) return false;
        using (X509Certificate2 leaf = new X509Certificate2(certificate))
        using (X509Chain chain = new X509Chain()) {
            chain.ChainPolicy.ExtraStore.AddRange(roots);
            chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
            chain.ChainPolicy.VerificationFlags = X509VerificationFlags.AllowUnknownCertificateAuthority;
            if (!chain.Build(leaf)) return false;
            foreach (X509ChainStatus status in chain.ChainStatus) {
                if ((status.Status & ~X509ChainStatusFlags.UntrustedRoot) != 0) return false;
            }
            if (chain.ChainElements.Count == 0) return false;
            string thumbprint = chain.ChainElements[chain.ChainElements.Count - 1].Certificate.Thumbprint;
            foreach (X509Certificate2 root in roots) if (root.Thumbprint == thumbprint) return true;
            return false;
        }
    }
}
'@ -ErrorAction Stop
}

function Get-BootstrapFile([string]$Base, [string]$Path, [string]$Scheme, [string]$Destination, [long]$Limit) {
    $uri = Get-BootstrapUri $Base $Path $Scheme
    $previous = [Net.ServicePointManager]::ServerCertificateValidationCallback
    try {
        if ($env:ZSETUP_CA_FILE -and $Scheme -eq 'https') {
            Initialize-BootstrapTrust
            [LinkeaseBootstrapTrust]::Configure($env:ZSETUP_CA_FILE)
            [Net.ServicePointManager]::ServerCertificateValidationCallback = [LinkeaseBootstrapTrust]::Callback
        }
        # Native PowerShell transport is only for the first dependency. OutFile
        # streams bytes; installer packages never pass through this function.
        Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $Destination -TimeoutSec 30 -MaximumRedirection 0 -ErrorAction Stop | Out-Null
        $length = (Get-Item -LiteralPath $Destination -ErrorAction Stop).Length
        if ($length -le 0 -or $length -gt $Limit) { throw 'bootstrap file exceeds size bound' }
        return $true
    } catch {
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        return $false
    } finally {
        [Net.ServicePointManager]::ServerCertificateValidationCallback = $previous
        if ('LinkeaseBootstrapTrust' -as [type]) { [LinkeaseBootstrapTrust]::Clear() }
    }
}

function Confirm-BootstrapHttp {
    if ($script:BootstrapInsecureConfirmed) { return }
    [Console]::Error.WriteLine('zsetup: all HTTPS bootstrap sources failed; HTTP and its checksum metadata can be replaced by an attacker.')
    if ($env:ZSETUP_CONFIRM_FILE) {
        $file = Get-Item -LiteralPath $env:ZSETUP_CONFIRM_FILE -ErrorAction Stop
        if ($file.Length -gt 1024) { throw 'zsetup: invalid confirmation file' }
        $answer = ([IO.File]::ReadAllText($file.FullName) -split '\r?\n')[0]
    } else {
        if ([Console]::IsInputRedirected) { throw 'zsetup: HTTP bootstrap refused because no interactive confirmation is available' }
        try { $answer = Read-Host 'Continue with insecure HTTP bootstrap? [y/N]' }
        catch { throw 'zsetup: HTTP bootstrap refused because no interactive confirmation is available' }
    }
    if (@('y', 'Y', 'yes', 'YES') -cnotcontains $answer) { throw 'zsetup: insecure HTTP bootstrap declined' }
    $script:BootstrapInsecureConfirmed = $true
    [Console]::Error.WriteLine('zsetup: user accepted insecure HTTP bootstrap')
}

function Get-BootstrapBases { return @($script:BootstrapPrimaryBases) + @($script:BootstrapFallbackBase | Where-Object { $_ }) }

function Get-BootstrapMetadata([string]$Scheme, [string]$Stable, [string]$Sums) {
    foreach ($base in (Get-BootstrapBases)) {
        if (-not (Get-BootstrapFile $base 'zsetup/stable-windows' $Scheme $Stable 128)) { continue }
        $version = [IO.File]::ReadAllText($Stable).TrimEnd([char[]]"`r`n")
        if ($version.Length -gt 64 -or $version -cnotmatch '^([0-9]+)\.([0-9]+)\.([0-9]+)([-+][A-Za-z0-9._+-]+)?$') { continue }
        try { $compatible = [Version]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3]) } catch { continue }
        if ($compatible -lt [Version]'0.3.0') { continue }
        if (-not (Get-BootstrapFile $base "zsetup/$version/SHA256SUMS" $Scheme $Sums 65536)) { continue }
        $hashes = @()
        foreach ($line in [IO.File]::ReadAllLines($Sums)) {
            $fields = @($line -split '\s+' | Where-Object { $_ })
            if ($fields.Count -eq 2 -and $fields[1].TrimStart('*') -ceq $script:BootstrapArtifact) { $hashes += $fields[0] }
        }
        if ($hashes.Count -ne 1 -or $hashes[0] -cnotmatch '^[0-9a-fA-F]{64}$') { continue }
        return @{ Version = $version; Sha256 = $hashes[0] }
    }
    return $null
}

function Test-BootstrapBinary([string]$Binary, [string]$Version, [string]$Sha256) {
    if (-not (Test-Path -LiteralPath $Binary -PathType Leaf)) { return $false }
    if ((Get-FileHash -LiteralPath $Binary -Algorithm SHA256 -ErrorAction Stop).Hash -ine $Sha256) { return $false }
    $stream = [IO.File]::OpenRead($Binary)
    try {
        if ($stream.Length -lt 64 -or $stream.Length -gt 16777216) { return $false }
        $head = New-Object byte[] 64
        if ($stream.Read($head, 0, 64) -ne 64 -or $head[0] -ne 77 -or $head[1] -ne 90) { return $false }
        $offset = [BitConverter]::ToUInt32($head, 60)
        if ($offset -gt 4096 -or $offset + 6 -gt $stream.Length) { return $false }
        $stream.Position = $offset
        $pe = New-Object byte[] 6
        if ($stream.Read($pe, 0, 6) -ne 6 -or [BitConverter]::ToUInt32($pe, 0) -ne 17744 -or [BitConverter]::ToUInt16($pe, 4) -ne 332) { return $false }
    } finally { $stream.Dispose() }
    $out = $Binary + '.stdout-' + [Guid]::NewGuid().ToString('N')
    $err = $out + '.stderr'
    $child = $null
    try {
        $child = Start-Process -FilePath $Binary -ArgumentList '--version' -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -ErrorAction Stop
        $ownedHandle = $child.Handle # PS5.1 retains the exit code after a fast process exits.
        if (-not $child.WaitForExit(5000)) { $child.Kill(); $child.WaitForExit(); return $false }
        $child.WaitForExit()
        if ($child.ExitCode -ne 0 -or (Get-Item -LiteralPath $out).Length -gt 128 -or (Get-Item -LiteralPath $err).Length -gt 0) { return $false }
        return [IO.File]::ReadAllText($out).TrimEnd([char[]]"`r`n") -ceq "zsetup $Version"
    } catch { return $false }
    finally {
        if ($null -ne $child) {
            if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit() }
            $child.Dispose()
        }
        Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
    }
}

function Get-ZsetupBootstrap {
    $work = if ($env:ZSETUP_ROOT) { $env:ZSETUP_ROOT } else { Join-Path ([IO.Path]::GetTempPath()) 'zsetup' }
    if (-not [IO.Path]::IsPathRooted($work)) { throw 'zsetup: ZSETUP_ROOT must be absolute' }
    $state = Join-Path $work 'bootstrap'
    New-Item -ItemType Directory -Path $state -Force -ErrorAction Stop | Out-Null
    $id = [Guid]::NewGuid().ToString('N')
    $stable = Join-Path $state ('.stable-' + $id)
    $sums = Join-Path $state ('.SHA256SUMS-' + $id)
    $candidate = $null
    try {
        $metadata = Get-BootstrapMetadata 'https' $stable $sums
        if ($null -eq $metadata) {
            Confirm-BootstrapHttp
            $metadata = Get-BootstrapMetadata 'http' $stable $sums
        }
        if ($null -eq $metadata) { throw 'zsetup: no source returned valid bootstrap metadata' }
        $rescue = Join-Path (Join-Path $work 'rescue') $metadata.Version
        $target = Join-Path $rescue 'zsetup.exe'
        $existing = @($env:ZSETUP_BIN, $target)
        $system = Get-Command zsetup.exe -CommandType Application -ErrorAction SilentlyContinue
        if ($system) { $existing += $system.Source }
        foreach ($file in $existing) {
            if ($file -and (Test-BootstrapBinary $file $metadata.Version $metadata.Sha256)) { return $file }
        }
        New-Item -ItemType Directory -Path $rescue -Force -ErrorAction Stop | Out-Null
        $candidate = Join-Path $rescue ('.zsetup.candidate-' + $id + '.exe')
        $downloaded = $false
        foreach ($base in (Get-BootstrapBases)) {
            if (Get-BootstrapFile $base "zsetup/$($metadata.Version)/$script:BootstrapArtifact" 'https' $candidate 16777216) { $downloaded = $true; break }
        }
        if (-not $downloaded) {
            Confirm-BootstrapHttp
            foreach ($base in (Get-BootstrapBases)) {
                if (Get-BootstrapFile $base "zsetup/$($metadata.Version)/$script:BootstrapArtifact" 'http' $candidate 16777216) { $downloaded = $true; break }
            }
        }
        if (-not $downloaded -or -not (Test-BootstrapBinary $candidate $metadata.Version $metadata.Sha256)) { throw 'zsetup: bootstrap checksum, architecture or complete version mismatch' }
        if (Test-Path -LiteralPath $target) { [IO.File]::Replace($candidate, $target, [NullString]::Value) }
        else { [IO.File]::Move($candidate, $target) }
        return $target
    } finally {
        foreach ($file in @($stable, $sums, $candidate)) { if ($file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue } }
    }
}

$script:ScoopInstallerVersion = '0.1.2'
$script:ScoopRuntimeId = '0.9.1-market.238d13be-windows-amd64'
$script:ScoopRuntimeSize = 24149573
$script:ScoopRuntimeSha256 = 'e2163542c5edf03327df537be56df9b17ebf22d0eacaafb93cd9ccef7d19bb9a'
$script:ScoopCoreCommit = 'e6aa3b366bdee8ed138c1e0f7b85192ebdd35d0f'
$script:ScoopCoreSize = 1289426
$script:ScoopCoreSha256 = 'fa96b15950f3726d2c9a35493e192eefe56d2eddba718e8121c32f7a19257a0a'
$script:ScoopMainCommit = '1eca0759af467b38ae87b9579dd545d35f5b9917'
$script:ScoopMainSize = 1266906
$script:ScoopMainSha256 = '4287b169ce39f3a6566da666ce3c8b73f450c887d9a71481485b2ad2ca951636'
$script:ScoopReceiptName = '.linkease-scoop-receipt.json'
$script:ScoopUtf8 = [Text.UTF8Encoding]::new($false)

function Get-ScoopHash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Assert-ScoopLockedFile([string]$Path, [long]$Size, [string]$Sha256, [string]$Label) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or $item.Attributes -band [IO.FileAttributes]::ReparsePoint -or
        $item.Length -ne $Size -or (Get-ScoopHash $Path) -cne $Sha256) {
        throw "scoop: $Label size, type or SHA256 mismatch"
    }
}

function Test-ScoopAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ScoopUserPath { return [Environment]::GetEnvironmentVariable('PATH', 'User') }
function Set-ScoopUserPath([string]$Value) { [Environment]::SetEnvironmentVariable('PATH', $Value, 'User') }

function Test-ScoopSafePath([string]$Path, [string]$Label) {
    if (-not $Path -or -not [IO.Path]::IsPathRooted($Path)) { throw "scoop: $Label must be absolute" }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $profile = [IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')
    if ($full -ceq $profile -or -not $full.StartsWith($profile + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "scoop: $Label must stay inside the current user profile"
    }
    if ($full -match '^(?i:[a-z]:\\(?:windows|program files(?: \(x86\))?|programdata))(?:\\|$)') { throw "scoop: $Label is system protected" }
    $probe = $full
    while ($probe -and (Test-Path -LiteralPath $probe)) {
        $item = Get-Item -LiteralPath $probe -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "scoop: $Label contains a reparse point" }
        $parent = Split-Path -Parent $probe
        if ($parent -ceq $probe) { break }
        $probe = $parent
    }
    return $full
}

function Test-ScoopFault([string]$Point) {
    if ($env:ZSETUP_SCOOP_FAIL_AFTER -ceq $Point) { throw "scoop: fault injection after $Point" }
}

function Write-ScoopJson([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 12 -Compress) + "`n"), $script:ScoopUtf8)
}

function Get-ScoopBootstrapPlan {
    return [ordered]@{
        schema_version = 1; operation = 'scoop-bootstrap'
        required_capabilities = @('download-gateway.v1', 'route.github-archive.v1')
        artifacts = @(
            [ordered]@{ role = 'core'; repository = 'ScoopInstaller/Scoop'; commit = $script:ScoopCoreCommit; url = "https://github.com/ScoopInstaller/Scoop/archive/$($script:ScoopCoreCommit).zip"; sha256 = $script:ScoopCoreSha256; size = $script:ScoopCoreSize },
            [ordered]@{ role = 'main'; repository = 'ScoopInstaller/Main'; commit = $script:ScoopMainCommit; url = "https://github.com/ScoopInstaller/Main/archive/$($script:ScoopMainCommit).zip"; sha256 = $script:ScoopMainSha256; size = $script:ScoopMainSize }
        )
    }
}

function Expand-ScoopFlatZip([string]$Archive, [string]$Destination, [string[]]$Expected) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Path $Destination -ErrorAction Stop | Out-Null
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $seen = @{}
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName
            if ($name -notmatch '^[A-Za-z0-9._-]+$' -or $seen.ContainsKey($name.ToLowerInvariant()) -or $entry.Name -cne $name) { throw 'scoop: unsafe or duplicate flat ZIP entry' }
            $seen[$name.ToLowerInvariant()] = $true
        }
        if ($seen.Count -ne $Expected.Count) { throw 'scoop: unexpected sealed/runtime ZIP entry count' }
        foreach ($name in $Expected) {
            if (-not $seen.ContainsKey($name.ToLowerInvariant())) { throw "scoop: missing ZIP entry $name" }
            $entry = $zip.GetEntry($name); $target = Join-Path $Destination $name
            $input = $entry.Open(); $output = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
        }
    } finally { $zip.Dispose() }
}

function Expand-VerifiedRuntimeBundle([string]$Archive, [string]$Destination) {
    Assert-ScoopLockedFile $Archive $script:ScoopRuntimeSize $script:ScoopRuntimeSha256 'runtime bundle'
    Expand-ScoopFlatZip $Archive $Destination @('identity.json', 'ks-cli.exe', 'kspeeder.exe', 'manifest.json')
    $manifest = Get-Content -LiteralPath (Join-Path $Destination 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($manifest.schema_version -ne 1 -or $manifest.bundle_id -cne $script:ScoopRuntimeId -or $manifest.platform -cne 'windows' -or $manifest.architecture -cne 'amd64' -or $manifest.files.Count -ne 3) { throw 'scoop: invalid runtime bundle manifest identity' }
    foreach ($record in $manifest.files) {
        if (@('identity.json', 'ks-cli.exe', 'kspeeder.exe') -cnotcontains $record.path) { throw 'scoop: runtime manifest contains an unknown file' }
        Assert-ScoopLockedFile (Join-Path $Destination $record.path) ([long]$record.size) $record.sha256 "runtime $($record.path)"
    }
    return $Destination
}

function Invoke-ZsetupRuntimeDownload([string]$Output) {
    $relative = "kspeeder/runtimes/$($script:ScoopRuntimeId)/runtime.zip"
    $urls = @("https://kspeeder.com/bin/runtimes/$($script:ScoopRuntimeId)/runtime.zip", "https://dl.istoreos.com/binary/$relative", "https://fw.d4ctech.com/binary/$relative")
    & $env:ZSETUP_BIN download -o $Output --sha256 $script:ScoopRuntimeSha256 --size $script:ScoopRuntimeSize @urls --fallback-url "https://fw.koolcenter.com/binary/$relative"
    if ($LASTEXITCODE -ne 0) { throw "scoop: zsetup runtime download failed with exit $LASTEXITCODE" }
    Assert-ScoopLockedFile $Output $script:ScoopRuntimeSize $script:ScoopRuntimeSha256 'downloaded runtime bundle'
}

function Invoke-AcceleratedBootstrap([string]$Runtime, [string]$Work) {
    $plan = Join-Path $Work 'bootstrap-plan.json'; $receipt = Join-Path $Work 'bootstrap-receipt.json'; $archives = Join-Path $Work 'accelerated-archives'
    Write-ScoopJson $plan (Get-ScoopBootstrapPlan)
    $cli = Join-Path $Runtime 'ks-cli.exe'
    & $cli runtime exec --service-binary (Join-Path $Runtime 'kspeeder.exe') --identity (Join-Path $Runtime 'identity.json') --require-capability download-gateway.v1 --require-capability route.github-archive.v1 -- $cli scoop bootstrap --service-binary (Join-Path $Runtime 'kspeeder.exe') --identity (Join-Path $Runtime 'identity.json') --plan $plan --staging $archives --receipt $receipt --require-accelerated --json
    if ($LASTEXITCODE -ne 0) { throw "scoop: accelerated bootstrap failed with exit $LASTEXITCODE" }
    $proof = Get-Content -LiteralPath $receipt -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($proof.status -cne 'passed' -or $proof.origin_fallback_allowed -ne $false -or $proof.artifacts.Count -ne 2) { throw 'scoop: invalid accelerated bootstrap receipt' }
    foreach ($record in $proof.artifacts) { if ($record.selected -cne 'admin_proxy' -or $record.sha256_verified -ne $true) { throw 'scoop: bootstrap did not use strict admin_proxy' } }
    Assert-ScoopLockedFile (Join-Path $archives 'core.zip') $script:ScoopCoreSize $script:ScoopCoreSha256 'Scoop Core'
    Assert-ScoopLockedFile (Join-Path $archives 'main.zip') $script:ScoopMainSize $script:ScoopMainSha256 'Scoop Main'
    return @{ Core = Join-Path $archives 'core.zip'; Main = Join-Path $archives 'main.zip'; Receipt = $receipt; Transport = 'kspeeder-admin-proxy' }
}

function Expand-VerifiedSealedBundle([string]$Archive, [string]$Work) {
    $sealed = Join-Path $Work 'sealed'
    Expand-ScoopFlatZip $Archive $sealed @('sealed-manifest.json', 'runtime-bundle.zip', 'runtime-release.json', 'bootstrap-plan.json', 'scoop-core.zip', 'scoop-main.zip')
    $manifest = Get-Content -LiteralPath (Join-Path $sealed 'sealed-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($manifest.schema_version -ne 1 -or $manifest.bundle_type -cne 'linkease-scoop-sealed-v1' -or $manifest.runtime_bundle_id -cne $script:ScoopRuntimeId -or $manifest.core_commit -cne $script:ScoopCoreCommit -or $manifest.main_commit -cne $script:ScoopMainCommit -or $manifest.files.Count -ne 5) { throw 'scoop: sealed bundle identity mismatch' }
    foreach ($record in $manifest.files) {
        if (@('runtime-bundle.zip', 'runtime-release.json', 'bootstrap-plan.json', 'scoop-core.zip', 'scoop-main.zip') -cnotcontains $record.path) { throw 'scoop: sealed manifest contains an unknown file' }
        Assert-ScoopLockedFile (Join-Path $sealed $record.path) ([long]$record.size) $record.sha256 "sealed $($record.path)"
    }
    Assert-ScoopLockedFile (Join-Path $sealed 'runtime-bundle.zip') $script:ScoopRuntimeSize $script:ScoopRuntimeSha256 'sealed runtime bundle'
    Assert-ScoopLockedFile (Join-Path $sealed 'scoop-core.zip') $script:ScoopCoreSize $script:ScoopCoreSha256 'sealed Scoop Core'
    Assert-ScoopLockedFile (Join-Path $sealed 'scoop-main.zip') $script:ScoopMainSize $script:ScoopMainSha256 'sealed Scoop Main'
    $release = Get-Content -LiteralPath (Join-Path $sealed 'runtime-release.json') -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($release.bundle_id -cne $script:ScoopRuntimeId -or $release.bundle_size -ne $script:ScoopRuntimeSize -or $release.bundle_sha256 -cne $script:ScoopRuntimeSha256) { throw 'scoop: sealed runtime release mismatch' }
    $plan = Get-Content -LiteralPath (Join-Path $sealed 'bootstrap-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($plan.artifacts.Count -ne 2 -or $plan.artifacts[0].commit -cne $script:ScoopCoreCommit -or $plan.artifacts[1].commit -cne $script:ScoopMainCommit) { throw 'scoop: sealed bootstrap plan mismatch' }
    return @{ Core = Join-Path $sealed 'scoop-core.zip'; Main = Join-Path $sealed 'scoop-main.zip'; Receipt = $null; Transport = 'sealed-bundle' }
}

function Expand-VerifiedScoopArchive([string]$Archive, [string]$Destination, [string]$Prefix, [long]$Size, [string]$Sha256) {
    Assert-ScoopLockedFile $Archive $Size $Sha256 $Prefix
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop | Out-Null
    $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'; $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $seen = @{}; $files = 0
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName
            if (-not $name.StartsWith($Prefix + '/', [StringComparison]::Ordinal) -or $name.Contains('\') -or $name.Contains(':')) { throw 'scoop: archive path escaped its locked prefix' }
            $relative = $name.Substring($Prefix.Length + 1); if (-not $relative) { continue }
            $isDirectory = -not $entry.Name
            if ($isDirectory) { $relative = $relative.TrimEnd('/') }
            if (-not $relative) { continue }
            foreach ($part in $relative.Split('/')) { if (-not $part -or $part -eq '.' -or $part -eq '..') { throw 'scoop: invalid archive path component' } }
            $key = $relative.ToLowerInvariant(); if ($seen.ContainsKey($key)) { throw 'scoop: duplicate archive path' }; $seen[$key] = $true
            $target = [IO.Path]::GetFullPath((Join-Path $Destination ($relative.Replace('/', '\'))))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'scoop: archive path traversal' }
            if ($isDirectory) { New-Item -ItemType Directory -Path $target -Force -ErrorAction Stop | Out-Null; continue }
            if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'scoop: archive symlink refused' }
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force -ErrorAction Stop | Out-Null
            $input = $entry.Open(); $output = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }; $files++
        }
        if ($files -lt 1) { throw 'scoop: empty archive refused' }
    } finally { $zip.Dispose() }
}

function Write-ScoopOwnedReceipt([string]$Root, [string]$Transport) {
    Write-ScoopJson (Join-Path $Root $script:ScoopReceiptName) ([ordered]@{
        schema_version = 1; owner = 'linkease-zsetup'; installer_version = $script:ScoopInstallerVersion; runtime_bundle_id = $script:ScoopRuntimeId; runtime_bundle_sha256 = $script:ScoopRuntimeSha256
        core_commit = $script:ScoopCoreCommit; core_sha256 = $script:ScoopCoreSha256; main_commit = $script:ScoopMainCommit; main_sha256 = $script:ScoopMainSha256; transport = $Transport
    })
}

function Test-ScoopOwnedCurrent([string]$Root) {
    $path = Join-Path $Root $script:ScoopReceiptName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    try { $receipt = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop } catch { return $false }
    return $receipt.owner -ceq 'linkease-zsetup' -and $receipt.installer_version -ceq $script:ScoopInstallerVersion -and $receipt.runtime_bundle_id -ceq $script:ScoopRuntimeId -and $receipt.runtime_bundle_sha256 -ceq $script:ScoopRuntimeSha256 -and $receipt.core_sha256 -ceq $script:ScoopCoreSha256 -and $receipt.main_sha256 -ceq $script:ScoopMainSha256 -and $receipt.core_commit -ceq $script:ScoopCoreCommit -and $receipt.main_commit -ceq $script:ScoopMainCommit -and (Test-Path -LiteralPath (Join-Path $Root 'apps\scoop\current\bin\scoop.ps1') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $Root 'buckets\main\bucket\7zip.json') -PathType Leaf)
}

function Write-ScoopShims([string]$Root) {
    $shims = Join-Path $Root 'shims'; New-Item -ItemType Directory -Path $shims -Force | Out-Null
    $ps1 = "`$path = Join-Path `$PSScriptRoot '..\apps\scoop\current\bin\scoop.ps1'`r`nif (`$MyInvocation.ExpectingInput) { `$input | & `$path @args } else { & `$path @args }`r`nexit `$LASTEXITCODE`r`n"
    $cmdTarget = '%~dp0..\apps\scoop\current\bin\scoop.ps1'
    $cmd = "@echo off`r`nwhere /q pwsh.exe`r`nif %errorlevel% equ 0 (pwsh -noprofile -ex unrestricted -file `"$cmdTarget`" %*) else (powershell -noprofile -ex unrestricted -file `"$cmdTarget`" %*)`r`n"
    [IO.File]::WriteAllText((Join-Path $shims 'scoop.ps1'), $ps1, $script:ScoopUtf8); [IO.File]::WriteAllText((Join-Path $shims 'scoop.cmd'), $cmd, $script:ScoopUtf8)
}

function Set-ScoopConfig([string]$ConfigPath, [string]$Root, [string]$Cache) {
    $value = [ordered]@{}
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) { $old = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop; foreach ($property in $old.PSObject.Properties) { $value[$property.Name] = $property.Value } }
    $value['root_path'] = $Root; $value['cache_path'] = $Cache
    New-Item -ItemType Directory -Path (Split-Path -Parent $ConfigPath) -Force | Out-Null
    $candidate = $ConfigPath + '.candidate-' + [Guid]::NewGuid().ToString('N')
    try { Write-ScoopJson $candidate $value; Move-Item -LiteralPath $candidate -Destination $ConfigPath -Force } finally { Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue }
}

function Add-ScoopUserPath([string]$Shim) {
    $parts = @((Get-ScoopUserPath) -split ';' | Where-Object { $_ -and $_ -ine $Shim })
    Set-ScoopUserPath (($Shim) + $(if ($parts.Count) { ';' + ($parts -join ';') } else { '' }))
}

function Test-ScoopInstalled([string]$Root, [string]$Work) {
    $stdout = Join-Path $Work 'scoop-version.stdout'; $stderr = Join-Path $Work 'scoop-version.stderr'
    $shim = (Join-Path $Root 'shims\scoop.ps1').Replace("'", "''")
    $command = "& '$shim' --version"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
    $output = if (Test-Path -LiteralPath $stdout) { [IO.File]::ReadAllText($stdout) } else { '' }
    $errorOutput = if (Test-Path -LiteralPath $stderr) { [IO.File]::ReadAllText($stderr) } else { '' }
    if ($process.ExitCode -ne 0 -or $output -notmatch 'Current Scoop version:') { throw "scoop: installed scoop --version failed: $errorOutput" }
}

function Remove-ScoopTreeJunctions([string]$Tree, [object[]]$Junctions) {
    foreach ($junction in @($Junctions)) {
        $path = Join-Path $Tree $junction.path
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or $item.LinkType -cne 'Junction' -or
            -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "scoop: expected transaction junction is missing: $($junction.path)"
        }
        $item.Attributes = [IO.FileAttributes]([int]$item.Attributes -band (-bnot [int][IO.FileAttributes]::ReadOnly))
        [IO.Directory]::Delete($path)
    }
}

function Commit-ScoopTransaction([string]$Root, [string]$Cache, [string]$ConfigPath, [string]$Stage, [object[]]$Junctions, [string]$Transport, [string]$Work) {
    $rootExisted = Test-Path -LiteralPath $Root; $backup = $Root + '.linkease-backup-' + [Guid]::NewGuid().ToString('N')
    $configExisted = Test-Path -LiteralPath $ConfigPath -PathType Leaf; $configBytes = if ($configExisted) { [IO.File]::ReadAllBytes($ConfigPath) } else { $null }
    $oldPath = Get-ScoopUserPath; $swapped = $false
    try {
        Test-ScoopFault 'after-stage'
        if ($rootExisted) { Move-Item -LiteralPath $Root -Destination $backup -ErrorAction Stop }
        Move-Item -LiteralPath $Stage -Destination $Root -ErrorAction Stop; $swapped = $true
        foreach ($junction in @($Junctions)) {
            $createdJunction = New-Item -ItemType Junction -Path (Join-Path $Root $junction.path) -Target (Join-Path $Root $junction.target) -ErrorAction Stop
            if ($junction.read_only) {
                $createdJunction.Attributes = $createdJunction.Attributes -bor [IO.FileAttributes]::ReadOnly
            }
        }
        Test-ScoopFault 'after-root-swap'; Set-ScoopConfig $ConfigPath $Root $Cache; Test-ScoopFault 'after-config'; Add-ScoopUserPath (Join-Path $Root 'shims'); Test-ScoopFault 'after-path'; Test-ScoopInstalled $Root $Work
    } catch {
        $failure = $_
        try {
            if ($swapped -and (Test-Path -LiteralPath $Root)) {
                Remove-ScoopTreeJunctions $Root $Junctions
                Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction Stop
            }
            if ($rootExisted -and (Test-Path -LiteralPath $backup)) { Move-Item -LiteralPath $backup -Destination $Root -ErrorAction Stop }
            if ($configExisted) { New-Item -ItemType Directory -Path (Split-Path -Parent $ConfigPath) -Force | Out-Null; [IO.File]::WriteAllBytes($ConfigPath, $configBytes) } else { Remove-Item -LiteralPath $ConfigPath -Force -ErrorAction SilentlyContinue }
            Set-ScoopUserPath $oldPath
        } catch { throw "scoop: rollback failed after: $($failure.Exception.Message); rollback: $($_.Exception.Message)" }
        throw $failure
    }
    if ($rootExisted) {
        Remove-ScoopTreeJunctions $backup $Junctions
        Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction Stop
    }
}

function Copy-ScoopOwnedTree([string]$Root, [string]$Stage) {
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $rootPrefix = $rootFull + '\'
    $queue = New-Object Collections.Queue
    $queue.Enqueue([pscustomobject]@{source=$rootFull;destination=$Stage})
    $junctions = @()
    while ($queue.Count -gt 0) {
        $directory = $queue.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory.source -Force -ErrorAction Stop)) {
            $relative = $item.FullName.Substring($rootPrefix.Length)
            $destination = Join-Path $Stage $relative
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $targets = @($item.Target)
                if (-not $item.PSIsContainer -or $item.LinkType -cne 'Junction' -or $targets.Count -ne 1) {
                    throw 'scoop: existing root contains an unsupported reparse point'
                }
                $targetFull = [IO.Path]::GetFullPath([string]$targets[0]).TrimEnd('\')
                if (-not $targetFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'scoop: existing root contains a junction outside the owned root'
                }
                $targetRelative = $targetFull.Substring($rootPrefix.Length)
                $sourceParts = @($relative.Split([char]92)); $targetParts = @($targetRelative.Split([char]92))
                if ($sourceParts.Count -lt 4 -or $targetParts.Count -lt 3 -or
                    $sourceParts[0] -ine 'apps' -or $targetParts[0] -ine 'persist' -or
                    $sourceParts[1] -ine $targetParts[1]) {
                    throw 'scoop: existing root contains a junction outside the Scoop persist layout'
                }
                $probe = $targetFull
                while ($probe -ine $rootFull) {
                    $targetItem = Get-Item -LiteralPath $probe -Force -ErrorAction Stop
                    if (-not $targetItem.PSIsContainer -or $targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                        throw 'scoop: persisted junction target contains a reparse point'
                    }
                    $parent = Split-Path -Parent $probe
                    if (-not $parent -or $parent -eq $probe) { throw 'scoop: persisted junction target escaped the owned root' }
                    $probe = $parent
                }
                $junctions += [pscustomobject]@{
                    path=$relative
                    target=$targetRelative
                    read_only=[bool]($item.Attributes -band [IO.FileAttributes]::ReadOnly)
                }
                continue
            }
            if ($item.PSIsContainer) {
                New-Item -ItemType Directory -Path $destination -Force -ErrorAction Stop | Out-Null
                $queue.Enqueue([pscustomobject]@{source=$item.FullName;destination=$destination})
            } else {
                Copy-Item -LiteralPath $item.FullName -Destination $destination -Force -ErrorAction Stop
            }
        }
    }
    return @($junctions)
}

function New-ScoopStage([string]$Root, [string]$Work, $Archives) {
    $stage = Join-Path $Work 'install-root'
    $junctions = @()
    if (Test-Path -LiteralPath $Root) {
        $receipt = Join-Path $Root $script:ScoopReceiptName
        if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
            if (@(Get-ChildItem -LiteralPath $Root -Force -ErrorAction Stop).Count -gt 0) { throw 'scoop: non-empty unowned installation root refused' }
        } else {
            $owned = Get-Content -LiteralPath $receipt -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if ($owned.owner -cne 'linkease-zsetup') { throw 'scoop: unowned installation root refused' }
            New-Item -ItemType Directory -Path $stage -Force | Out-Null
            $junctions = @(Copy-ScoopOwnedTree $Root $stage)
        }
    }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    $preserveMain = Test-Path -LiteralPath (Join-Path $stage 'buckets\main') -PathType Container
    foreach ($relative in @('apps\scoop\current')) { Remove-Item -LiteralPath (Join-Path $stage $relative) -Recurse -Force -ErrorAction SilentlyContinue }
    $junctions = @($junctions | Where-Object {
        $_.path -notmatch '^(?i:apps\\scoop\\current)(?:\\|$)'
    })
    Expand-VerifiedScoopArchive $Archives.Core (Join-Path $stage 'apps\scoop\current') ("Scoop-" + $script:ScoopCoreCommit) $script:ScoopCoreSize $script:ScoopCoreSha256
    if (-not $preserveMain) {Expand-VerifiedScoopArchive $Archives.Main (Join-Path $stage 'buckets\main') ("Main-" + $script:ScoopMainCommit) $script:ScoopMainSize $script:ScoopMainSha256}
    Write-ScoopShims $stage; Write-ScoopOwnedReceipt $stage $Archives.Transport
    if ($Archives.Receipt) {Copy-Item -LiteralPath $Archives.Receipt -Destination (Join-Path $stage '.linkease-scoop-bootstrap-receipt.json') -Force}
    return [pscustomobject]@{path=$stage;junctions=@($junctions)}
}

function Get-ScoopInstallOptions([string[]]$Arguments) {
    $options = @{ RuntimeBundle = $null; Scope = 'user'; Root = $null; Cache = $null; Bundle = $null; AllowAdmin = $false }
    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        switch -CaseSensitive ($Arguments[$index]) {
            '--installer-scope' { if (++$index -ge $Arguments.Count) { throw 'scoop: missing scope value' }; $options.Scope = $Arguments[$index] }
            '--installer-root' { if (++$index -ge $Arguments.Count) { throw 'scoop: missing root value' }; $options.Root = $Arguments[$index] }
            '--installer-cache' { if (++$index -ge $Arguments.Count) { throw 'scoop: missing cache value' }; $options.Cache = $Arguments[$index] }
            '--installer-runtime-bundle' { if (++$index -ge $Arguments.Count) { throw 'scoop: missing runtime bundle value' }; $options.RuntimeBundle = $Arguments[$index] }
            '--installer-bundle' { if (++$index -ge $Arguments.Count) { throw 'scoop: missing bundle value' }; $options.Bundle = $Arguments[$index] }
            '--installer-allow-admin' { $options.AllowAdmin = $true }
            default { throw "scoop: unknown installer argument $($Arguments[$index])" }
        }
    }
    if ($options.Scope -cne 'user') { throw 'scoop: only --installer-scope user is supported' }
    if (-not $options.Root) { $options.Root = Join-Path $env:USERPROFILE 'scoop' }; if (-not $options.Cache) { $options.Cache = Join-Path $options.Root 'cache' }
    return $options
}

function Invoke-ScoopBusinessUnlocked {
    param([string[]]$InstallerArguments)
    if ($InstallerArguments.Count -ge 3 -and $InstallerArguments[0] -ceq '--explain' -and $InstallerArguments[1] -ceq '--json' -and $InstallerArguments[2] -ceq '--') {
        $literal = if ($InstallerArguments.Count -gt 3) { @($InstallerArguments[3..($InstallerArguments.Count - 1)]) } else { @() }
        return [ordered]@{ schema_version = 1; operation = 'scoop-install-plan'; milestone = 'M6'; executable = $true; arguments = $literal; runtime_bundle_id = $script:ScoopRuntimeId; core_commit = $script:ScoopCoreCommit; main_commit = $script:ScoopMainCommit } | ConvertTo-Json -Depth 5 -Compress
    }
    $options = Get-ScoopInstallOptions $InstallerArguments
    if ((Test-ScoopAdministrator) -and -not $options.AllowAdmin) { throw 'scoop: elevated administrator install is rejected by default' }
    $root = Test-ScoopSafePath $options.Root 'installation root'; $cache = Test-ScoopSafePath $options.Cache 'cache path'
    if ($options.RuntimeBundle -and -not [IO.Path]::IsPathRooted($options.RuntimeBundle)) { throw 'scoop: runtime bundle path must be absolute' }
    if ($options.Bundle) {
        if (-not [IO.Path]::IsPathRooted($options.Bundle)) { throw 'scoop: sealed bundle path must be absolute' }
        $bundle = [IO.Path]::GetFullPath($options.Bundle); $bundleItem = Get-Item -LiteralPath $bundle -Force -ErrorAction Stop
        if ($bundleItem.PSIsContainer -or $bundleItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'scoop: sealed bundle must be a regular file' }
    }
    $configPath = Join-Path $env:USERPROFILE '.config\scoop\config.json'
    if (Test-ScoopOwnedCurrent $root) {
        Set-ScoopConfig $configPath $root $cache; Add-ScoopUserPath (Join-Path $root 'shims')
        return [ordered]@{ schema_version = 1; status = 'passed'; operation = 'scoop-install'; idempotent = $true; root = $root; cache = $cache } | ConvertTo-Json -Compress
    }
    $parent = Split-Path -Parent $root; New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
    $work = Join-Path $parent ('.linkease-scoop-' + [Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $work -ErrorAction Stop | Out-Null
    try {
        if ($options.Bundle) { $archives = Expand-VerifiedSealedBundle $bundle $work }
        else {
            $runtimeZip = if ($options.RuntimeBundle) { [IO.Path]::GetFullPath($options.RuntimeBundle) } else { Join-Path $work 'runtime-bundle.zip' }
            if (-not $options.RuntimeBundle) { Invoke-ZsetupRuntimeDownload $runtimeZip }
            $runtime = Expand-VerifiedRuntimeBundle $runtimeZip (Join-Path $work 'runtime')
            $archives = Invoke-AcceleratedBootstrap $runtime $work
        }
        $stage = New-ScoopStage $root $work $archives; Commit-ScoopTransaction $root $cache $configPath $stage.path $stage.junctions $archives.Transport $work
        return [ordered]@{ schema_version = 1; status = 'passed'; operation = 'scoop-install'; idempotent = $false; transport = $archives.Transport; root = $root; cache = $cache; runtime_bundle_id = $script:ScoopRuntimeId; core_commit = $script:ScoopCoreCommit; main_commit = $script:ScoopMainCommit } | ConvertTo-Json -Compress
    } finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

# Standalone owner invocations coordinate across KAIPlus instances and sessions.
function Invoke-ScoopBusiness {
    param([string[]]$InstallerArguments)
    if ($InstallerArguments.Count -gt 0 -and $InstallerArguments[0] -ceq '--explain') {return Invoke-ScoopBusinessUnlocked -InstallerArguments $InstallerArguments}
    $options=Get-ScoopInstallOptions $InstallerArguments
    $root=Test-ScoopSafePath $options.Root 'installation root'
    if ((Test-ScoopAdministrator) -and -not $options.AllowAdmin) {throw 'scoop: elevated administrator install is rejected by default'}
    New-Item -ItemType Directory -Path (Split-Path -Parent $root) -Force | Out-Null
    $handle=$null;$deadline=[DateTime]::UtcNow.AddSeconds(30)
    while ($null -eq $handle) {
        try {$handle=[IO.File]::Open(($root+'.owner.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
        catch [IO.IOException] {if([DateTime]::UtcNow -ge $deadline){throw 'scoop: another owner operation holds the installation lock'};Start-Sleep -Milliseconds 100}
    }
    try {Invoke-ScoopBusinessUnlocked -InstallerArguments $InstallerArguments} finally {$handle.Dispose()}
}

$script:ScoopEntryArguments = @($args)
try {
    if ($env:ZSETUP_INSTALLER_MODE -cne '1') {
        $env:ZSETUP_BIN = Get-ZsetupBootstrap
        $env:ZSETUP_SOURCE_BASES = $script:BootstrapPrimaryBases -join ' '
        $env:ZSETUP_SOURCE_FALLBACK = $script:BootstrapFallbackBase
    }
    if (-not $env:ZSETUP_BIN -or -not [IO.Path]::IsPathRooted($env:ZSETUP_BIN)) {
        throw 'scoop: trusted absolute ZSETUP_BIN is required'
    }
    Invoke-ScoopBusiness -InstallerArguments $script:ScoopEntryArguments
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 17
}
