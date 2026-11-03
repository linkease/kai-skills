param(
    [ValidateSet('Probe','Plan','Ensure')][string]$Action = 'Probe',
    [string]$TrustedPath
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
trap {
    [ordered]@{schemaVersion=1;tool='bash';platform='windows';status='failed';
        reason=$_.Exception.Message;exitCode=11}|ConvertTo-Json -Compress
    exit 11
}
$candidates = @()
if ($TrustedPath) { $candidates += $TrustedPath }
foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
    if ($root) { $candidates += (Join-Path $root 'Git\bin\bash.exe'); $candidates += (Join-Path $root 'Programs\Git\bin\bash.exe') }
}
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($git) { $candidates += (Join-Path (Split-Path (Split-Path $git.Source)) 'bin\bash.exe') }
$candidates += 'C:\msys64\usr\bin\bash.exe'
function Find-Bash {
    foreach ($candidate in $candidates) {
        if ($candidate.Replace('/','\') -match '\\(System32|Sysnative)\\bash\.exe$') { continue }
        if (!(Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $absolute = (Resolve-Path -LiteralPath $candidate).Path
        if ($absolute.Replace('/','\') -match '\\(System32|Sysnative)\\bash\.exe$') { continue }
        $version = & $absolute --noprofile --norc -c 'printf %s "$BASH_VERSION"'
        if ($LASTEXITCODE -eq 0 -and $version -match '^(\d+)\.(\d+)') {
            if ([int]$Matches[1] -gt 3 -or ([int]$Matches[1] -eq 3 -and [int]$Matches[2] -ge 2)) {
                return [ordered]@{schemaVersion=1;tool='bash';platform='windows';status='reused';path=$absolute;version=$version;exitCode=0}
            }
        }
    }
    return $null
}
$found = Find-Bash
if ($found) { $found | ConvertTo-Json -Compress; exit 0 }
$manager = Get-Command winget.exe -ErrorAction SilentlyContinue
$command = @('winget.exe','install','--id','Git.Git','--exact','--source','winget','--disable-interactivity')
if (!$manager) {
    [ordered]@{schemaVersion=1;tool='bash';platform='windows';status='unavailable';reason='Git Bash absent and winget unavailable';nextStep='Install a trusted Git for Windows or MSYS2 distribution, then supply its absolute bash.exe path';commands=@();exitCode=18}|ConvertTo-Json -Compress
    exit 18
}
if ($Action -ne 'Ensure') {
    [ordered]@{schemaVersion=1;tool='bash';platform='windows';status='missing';commands=@(,$command);exitCode=0}|ConvertTo-Json -Depth 5 -Compress
    exit 0
}
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $manager.Source
$info.Arguments = 'install --id Git.Git --exact --source winget --disable-interactivity'
$info.UseShellExecute = $false
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$process = [Diagnostics.Process]::Start($info)
$output = $process.StandardOutput.ReadToEndAsync()
$errors = $process.StandardError.ReadToEndAsync()
$process.WaitForExit()
[Console]::Error.Write($output.GetAwaiter().GetResult())
[Console]::Error.Write($errors.GetAwaiter().GetResult())
if ($process.ExitCode -ne 0) {
    $exitCode = 11
    if ($process.ExitCode -gt 0 -and $process.ExitCode -le 255) { $exitCode = $process.ExitCode }
    [ordered]@{schemaVersion=1;tool='bash';platform='windows';status='failed';
        reason='native Git installer failed';nativeExitCode=$process.ExitCode;exitCode=$exitCode}|ConvertTo-Json -Compress
    exit $exitCode
}
$found = Find-Bash
if (!$found) {
    [ordered]@{schemaVersion=1;tool='bash';platform='windows';status='failed';
        reason='The package manager completed but no compatible native Bash was found.';exitCode=19}|ConvertTo-Json -Compress
    exit 19
}
$found.status = 'installed'
$found | ConvertTo-Json -Compress
