# Query-only adapter: existing native providers, no installation or refresh.
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::InputEncoding=New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
try {
    $r=[Console]::In.ReadToEnd()|ConvertFrom-Json
    $name=[string]$r.software
    if($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$'){throw 'invalid-name'}
    $provider=[string]$r.provider
    if($provider -notin @('','auto','scoop','winget')){throw 'native-provider-required'}
    $installed='';$candidate='';$comparison='unknown';$source=@{id=$provider;freshness='cache-unverified';fetchedAt=$null}
    if($provider -in @('','auto')){
        . (Join-Path $PSScriptRoot 'windows-scoop.ps1')
        . (Join-Path $PSScriptRoot 'windows-winget.ps1')
        . (Join-Path $PSScriptRoot 'windows-auto.ps1')
        $result=Task-QueryAutomaticWindows $r
    } elseif($provider -eq 'scoop'){
        . (Join-Path $PSScriptRoot 'windows-scoop.ps1')
        $result=Task-QueryScoop $r
    } else {
        . (Join-Path $PSScriptRoot 'windows-winget.ps1')
        $result=Task-QueryWinGet $r
    }
    $result|ConvertTo-Json -Depth 5 -Compress
    if($result.reason){exit 18}
    exit 0
} catch {
    # Native exceptions can contain source credentials; return a stable category.
    $reason='native-provider-query-unavailable'
    $known=@('invalid-name','native-provider-required','scoop-unavailable','no-unique-native-candidate',
        'unconfirmed-scoop-source','unconfirmed-scoop-prefix','installed-scoop-manifest-missing',
        'installed-scoop-version-missing','incomplete-native-catalog','native-source-conflict')
    if($_.Exception.Message -cin $known){$reason=$_.Exception.Message}
    @{reason=$reason;stage='windows-provider';functionalValidation='not-run'}|ConvertTo-Json -Compress
    exit 18
}
