# Native Windows entry; only reuse an existing verified Git Bash.
param([ValidateSet('inspect','plan','apply')][string]$Operation,
      [Parameter(Mandatory=$true)][string]$RequestFile)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
try {
    $bootstrap=Join-Path $PSScriptRoot '../../kai-tool-bootstrap/scripts/bootstrap-bash.ps1'
    $native=Join-Path $PSHOME 'powershell.exe'
    $raw=& $native -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bootstrap -Action Probe
    $code=$LASTEXITCODE
    $bash=$raw|Out-String|ConvertFrom-Json
    if($code -ne 0 -or $bash.status -ne 'reused'){
        @{protocol='software-task/v1';schemaVersion=1;status='blocked';reason='compatible-bash-required';nativeExitCode=$code;effects=@();details=@{runtime=$bash}}|ConvertTo-Json -Depth 8 -Compress
        exit 21
    }
    $env:ZSETUP_TASK_WINDOWS_ADAPTER_DIR=$PSScriptRoot
    & $bash.path --noprofile --norc ((Join-Path $PSScriptRoot 'software-task.sh').Replace('\','/')) $Operation ($RequestFile.Replace('\','/'))
    exit $LASTEXITCODE
} catch {
    @{protocol='software-task/v1';schemaVersion=1;status='blocked';reason='native-entry-unavailable';nativeExitCode=11;effects=@();details=@{}}|ConvertTo-Json -Compress
    exit 21
}
