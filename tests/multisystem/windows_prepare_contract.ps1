param([Parameter(Mandatory=$true)][string]$Scripts)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$native=Join-Path $PSHOME 'powershell.exe'
function Run-Case($body,$status,$expected) {
    $prefix="[Console]::OutputEncoding=New-Object Text.UTF8Encoding(`$false);`$ProgressPreference='SilentlyContinue';"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($prefix+$body))
    $raw=& $native -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded
    $code=$LASTEXITCODE
    $value=$raw|Out-String|ConvertFrom-Json
    if($code -ne $expected -or $value.status -ne $status){throw "Wrong result: $code $raw"}
    return @{status=$status;exitCode=$code}
}
$bash=(Join-Path $Scripts 'bootstrap-bash.ps1').Replace("'","''")
$prepare=(Join-Path $Scripts 'prepare.ps1').Replace("'","''")
# Process-local environment only; neither remove Git nor change the real PATH.
$missing="`$env:ProgramFiles='C:\kai-test-absent';`${env:ProgramFiles(x86)}=`$env:ProgramFiles;`$env:LOCALAPPDATA=`$env:ProgramFiles;`$env:PATH=`$env:SystemRoot+'\System32'; & '$bash' -Action Plan; exit `$LASTEXITCODE"
$conflict="& '$prepare' -Action Ensure -TrustedBash 'C:\kai-test-absent\bash.exe'; exit `$LASTEXITCODE"
@{missing=(Run-Case $missing 'unavailable' 18);selected=(Run-Case $conflict 'preparation-required' 17)}|ConvertTo-Json -Depth 5 -Compress
exit 0
