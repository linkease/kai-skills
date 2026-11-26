[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$ServiceName,
    [Parameter(Mandatory)][ValidateSet('Start','Stop','Restart')][string]$Action
)
$ErrorActionPreference = 'Stop'
$service = Get-Service -Name $ServiceName
[ordered]@{
    schemaVersion=1
    target=[ordered]@{service=$service.Name; currentStatus=[string]$service.Status}
    change=[ordered]@{action=$Action; authorization='executor-policy'}
    verify=[ordered]@{expectedStatus=$(if ($Action -eq 'Stop') {'Stopped'} else {'Running'})}
} | ConvertTo-Json -Depth 4 -Compress
