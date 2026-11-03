[CmdletBinding()]
param(
    [ValidateRange(1, 50)]
    [int]$MaxEvents = 10
)

$ErrorActionPreference = 'Stop'
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$fixedDisks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' | ForEach-Object {
    [ordered]@{
        device = $_.DeviceID
        sizeBytes = [uint64]$_.Size
        freeBytes = [uint64]$_.FreeSpace
    }
})
$services = @(Get-Service)
$events = @(Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddHours(-24)} -MaxEvents $MaxEvents -ErrorAction SilentlyContinue | ForEach-Object {
    [ordered]@{
        time = $_.TimeCreated.ToUniversalTime().ToString('o')
        id = $_.Id
        provider = $_.ProviderName
        message = [string]$_.Message
    }
})

$result = [ordered]@{
    schemaVersion = 1
    os = [ordered]@{
        caption = $os.Caption
        version = $os.Version
        architecture = $os.OSArchitecture
        lastBoot = $os.LastBootUpTime.ToUniversalTime().ToString('o')
    }
    fixedDisks = $fixedDisks
    serviceTotals = [ordered]@{
        running = @($services | Where-Object Status -eq 'Running').Count
        stopped = @($services | Where-Object Status -eq 'Stopped').Count
    }
    recentCriticalEvents = $events
    truncated = $false
}

$json = $result | ConvertTo-Json -Depth 6 -Compress
if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 8192) {
    $result.recentCriticalEvents = @()
    $result.truncated = $true
    $json = $result | ConvertTo-Json -Depth 6 -Compress
}
if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 8192) {
    throw 'diagnostic output exceeds 8 KiB after truncation'
}
$json
