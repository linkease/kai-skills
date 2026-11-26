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
$queryErrors = @()
try {
$events = @(Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddHours(-24)} -MaxEvents $MaxEvents -ErrorAction Stop | ForEach-Object {
    [ordered]@{
        time = $_.TimeCreated.ToUniversalTime().ToString('o')
        id = $_.Id
        provider = $_.ProviderName
        message = [string]$_.Message
    }
})

} catch {
    if($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*'){$events=@()}
    else {$events=$null;$queryErrors+=@{code='EVENT_QUERY_FAILED';message='System event logs could not be read; no absence was inferred.'}}
}

$result = [ordered]@{
    schemaVersion = 1
    readOnly = $true
    observedAt = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    errors = $queryErrors
    untrustedData = $true
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
    # Keep failure visible rather than deleting all critical events and claiming a full result.
    @{schemaVersion=1;readOnly=$true;operationStatus='failed';errors=@(@{code='RESULT_LIMIT';message='Selected diagnostics exceed 8192 bytes; no truncated event set was accepted.'});truncated=$false}|ConvertTo-Json -Compress
    exit 1
}
$json
