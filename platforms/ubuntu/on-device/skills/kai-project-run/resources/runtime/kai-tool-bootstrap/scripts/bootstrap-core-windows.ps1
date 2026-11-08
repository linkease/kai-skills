# Called only on the native Windows target; stdout is the verified executable.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
try {
    # The shell caller verifies jq-owner.sha256 before entering this script.
    # Preserve the canonical owner's HTTPS, metadata, PE and version checks.
    . (Join-Path $PSScriptRoot '../resources/bootstrap-windows.ps1')
    $binary = Get-ZsetupBootstrap
    [Console]::Out.WriteLine($binary)
    exit 0
} catch {
    [Console]::Error.WriteLine('Native zsetup bootstrap: ' + $_.Exception.Message)
    exit 11
}
