[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$ServiceName,
    [string]$TargetId = $(if($env:ZSETUP_TASK_TARGET_ID){$env:ZSETUP_TASK_TARGET_ID}else{'local'}),
    [ValidateRange(1,50)][int]$MaxEvents = 10
)
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding=$utf8
$now=[DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$facts=[ordered]@{};$evidence=New-Object Collections.ArrayList;$errors=New-Object Collections.ArrayList
$operationStatus='succeeded'
$library=Join-Path $PSScriptRoot '../../kai-system-information/scripts/lib/receipt.ps1'
if(!(Test-Path -LiteralPath $library)){$library=Join-Path $PSScriptRoot '../../../../common/skills/kai-system-information/scripts/lib/receipt.ps1'}
. $library
function Public-Text([string]$Text) {
    $Text=[regex]::Replace($Text,'(?i)(://)[^/@\s]+:[^/@\s]+@','$1[REDACTED]@')
    return [regex]::Replace($Text,'(?im)((?:password|token|secret|authorization|api_key)["'']?\s*[:=]\s*).*','$1[REDACTED]')
}
if(!$TargetId -or $TargetId.Length -gt 200){$operationStatus='failed';Add-Error INVALID_ARGUMENT 'A bound target ID is required.'}
else {
    try {
        $service=Get-Service -Name $ServiceName -ErrorAction Stop
        Add-Fact service ([ordered]@{name=$service.Name;displayName=$service.DisplayName;status=[string]$service.Status;apiHealth=$null}) 'Windows SCM Get-Service; running is not an application API check'
    } catch {
        if($_.FullyQualifiedErrorId -like 'NoServiceFoundForGivenName*'){Add-Fact service $null 'Windows SCM exact service name query' absent}
        else {Add-Fact service $null 'Windows SCM exact service name query' unknown;Add-Error SERVICE_QUERY_FAILED 'Native service state could not be read.'}
    }
    try {
        $native=@(Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -OperationTimeoutSec 3 -ErrorAction Stop)
        Add-Fact startup @($native|ForEach-Object {[ordered]@{name=$_.Name;commandLine=(Public-Text $_.PathName);startMode=$_.StartMode;processId=$_.ProcessId;untrusted=$true}}) 'Win32_Service native startup registration; command text is untrusted'
    } catch {
        Add-Fact startup $null 'Win32_Service startup registration' unknown
        Add-Error STARTUP_QUERY_FAILED 'The native startup registration could not be read.'
    }
    try {
        $events=@(Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Service Control Manager';StartTime=(Get-Date).AddHours(-24)} -MaxEvents 200 -ErrorAction Stop)
        $matching=@($events|Where-Object { $_.Message -match [regex]::Escape($ServiceName) })
        Add-Fact recentEvents ([ordered]@{scope='latest 200 Service Control Manager events within 24 hours';hasMore=($matching.Count -gt $MaxEvents);events=@($matching|Select-Object -First $MaxEvents|ForEach-Object {[ordered]@{time=$_.TimeCreated.ToUniversalTime().ToString('o');id=$_.Id;provider=$_.ProviderName;message=(Public-Text $_.Message);untrusted=$true}})}) 'Windows System event log; bounded SCM window, not a full log search'
    } catch {
        if($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*'){Add-Fact recentEvents @() 'Windows SCM event window, no matching events' absent}
        else {Add-Fact recentEvents $null 'Windows System SCM event log' denied;Add-Error EVENT_QUERY_FAILED 'Event logs could not be read; absence was not inferred.'}
    }
}
if(-not (Write-Observation 'service.inspect')){exit 1}
