[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$ServiceName)
$ErrorActionPreference = 'Stop'
$service = Get-Service -Name $ServiceName
$events = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddHours(-24)} -MaxEvents 50 -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -in 7000,7001,7009,7011,7023,7024,7031,7034 -and $_.Message -match [regex]::Escape($ServiceName) } |
    Select-Object -First 10 |
    ForEach-Object { [ordered]@{time=$_.TimeCreated.ToUniversalTime().ToString('o'); id=$_.Id; provider=$_.ProviderName; message=[string]$_.Message} })
[ordered]@{schemaVersion=1; service=[ordered]@{name=$service.Name; displayName=$service.DisplayName; status=[string]$service.Status}; recentEvents=$events} |
    ConvertTo-Json -Depth 5 -Compress
