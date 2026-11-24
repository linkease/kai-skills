# Native Windows read entry; no Bash/jq bootstrap, download or source refresh.
param([ValidateSet('search','detail','inspect')][string]$Operation,
      [Parameter(Mandatory=$true)][string]$RequestFile)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$OutputEncoding=[Console]::OutputEncoding
$privateLog=$null
$script:QueryScriptsRoot=$PSScriptRoot
try {
    $file=Get-Item -LiteralPath $RequestFile -Force
    if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 8192){throw 'invalid-request'}
    $request=[IO.File]::ReadAllText($file.FullName)|ConvertFrom-Json
    if(@($request.PSObject.Properties.Name|Where-Object {$_ -notin @('targetId','query','id','software','provider','limit')}).Count){throw 'invalid-request'}
    foreach($field in @('targetId','query','id','software','provider')){if($null -ne $request.$field -and $request.$field -isnot [string]){throw 'invalid-request'}}
    $target=[string]$request.targetId;$expected=[string]$env:ZSETUP_TASK_TARGET_ID;if(!$expected){$expected='local'}
    if(!$target -or $target -cne $expected){throw 'target-mismatch'}
    $limit=3;if($null -ne $request.limit){if($request.limit -is [string] -or $request.limit -is [bool] -or [double]$request.limit -ne [math]::Floor([double]$request.limit)){throw 'invalid-limit'};$limit=[int]$request.limit}
    if($limit -lt 1 -or $limit -gt 10){throw 'invalid-limit'}
    $query=[string]$request.query;if(!$query){$query=[string]$request.id};if(!$query){$query=[string]$request.software}
    if(!$query -or $query.StartsWith('-') -or $query.Length -gt 256){throw 'query-required'}
    $provider=[string]$request.provider
    $native=Join-Path $PSHOME 'powershell.exe';if(!(Test-Path -LiteralPath $native)){$native=Join-Path $PSHOME 'pwsh'}
    . (Join-Path $PSScriptRoot 'query/result.ps1')
    . (Join-Path $PSScriptRoot 'query/windows.ps1')
    $privateLog=[IO.Path]::GetTempFileName()
    Query-Windows
} catch {
    # Native diagnostics and arbitrary provider fields never cross the query boundary.
    $known=@('invalid-request','target-mismatch','invalid-limit','query-required','source-qualified-id-required','unsupported-provider','provider-query-failed','invalid-provider-identity','query-result-too-large')
    $reason=[string]$_.Exception.Message;if($reason -notin $known){$reason='query-unavailable'}
    @{protocol='software-query/v1';schemaVersion=1;status='blocked';reason=$reason;items=@();effects=@()}|ConvertTo-Json -Compress
    exit 21
} finally {if($privateLog){Remove-Item -LiteralPath $privateLog -Force -ErrorAction SilentlyContinue}}
