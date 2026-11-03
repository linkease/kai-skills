[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$ServiceName,
    [Parameter(Mandatory)][ValidateSet('Start','Stop','Restart')][string]$Action
)
$ErrorActionPreference = 'Stop'
if ($env:TARGET_CHANGE_APPROVED -ne 'YES') {
    throw 'apply requires TARGET_CHANGE_APPROVED=YES after scoped user approval'
}
$service = Get-Service -Name $ServiceName
switch ($Action) {
    'Start' { Start-Service -InputObject $service }
    'Stop' { Stop-Service -InputObject $service }
    'Restart' { Restart-Service -InputObject $service }
}
[ordered]@{schemaVersion=1; service=$service.Name; action=$Action; applied=$true} | ConvertTo-Json -Compress
