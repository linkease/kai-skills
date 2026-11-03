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
    change=[ordered]@{action=$Action; requiresApproval=$true}
    verify=[ordered]@{expectedStatus=$(if ($Action -eq 'Stop') {'Stopped'} else {'Running'})}
    rollback=$(if ($Action -eq 'Stop') {'Start'} elseif ($service.Status -eq 'Stopped') {'Stop'} else {'None'})
} | ConvertTo-Json -Depth 4 -Compress
