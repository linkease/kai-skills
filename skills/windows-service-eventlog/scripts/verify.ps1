[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$ServiceName,
    [Parameter(Mandatory)][ValidateSet('Running','Stopped')][string]$ExpectedStatus
)
$ErrorActionPreference = 'Stop'
$service = Get-Service -Name $ServiceName
$actual = [string]$service.Status
[ordered]@{schemaVersion=1; service=$service.Name; expected=$ExpectedStatus; actual=$actual; ok=($actual -eq $ExpectedStatus)} |
    ConvertTo-Json -Compress
if ($actual -ne $ExpectedStatus) { exit 1 }
