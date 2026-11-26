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
