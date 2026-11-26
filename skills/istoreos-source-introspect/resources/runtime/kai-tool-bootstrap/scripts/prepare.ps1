# Native Windows first entry. Bash, jq and zsetup may all be absent.
param([ValidateSet('Probe','Plan','Ensure')][string]$Action='Probe', [string]$TrustedBash)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
try {
    # Child process isolates the existing bootstrap's exit from this coordinator.
    $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
        '-File',(Join-Path $PSScriptRoot 'bootstrap-bash.ps1'),'-Action',$Action)
    if($TrustedBash){$arguments+=@('-TrustedPath',$TrustedBash)}
    $raw=& (Join-Path $PSHOME 'powershell.exe') @arguments
    $code=$LASTEXITCODE
    $bash=$raw|Out-String|ConvertFrom-Json
    if($code -ne 0 -or $bash.status -notin @('reused','installed')) {
        @{schemaVersion=1;protocol='kai-runtime/v1';ready=$false;status='preparation-required';
          stage='bash';tools=@{bash=$bash};exitCode=$code}|ConvertTo-Json -Depth 8 -Compress
        exit $code
    }
    # Use positional argv, never interpolate target paths into Bash expressions.
    $entry=(Join-Path $PSScriptRoot 'prepare-runtime.sh').Replace('\','/')
    & $bash.path --noprofile --norc $entry $Action.ToLowerInvariant()
    exit $LASTEXITCODE
} catch {
    @{schemaVersion=1;protocol='kai-runtime/v1';ready=$false;status='failed';stage='prepare';
      reason=$_.Exception.Message;exitCode=11}|ConvertTo-Json -Compress
    exit 11
}
