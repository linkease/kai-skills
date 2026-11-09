param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$Zsetup
)
$ErrorActionPreference = 'Stop'
$rootPath = (Resolve-Path -LiteralPath $Root).Path
$zsetupPath = (Resolve-Path -LiteralPath $Zsetup).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('kai-skills-native-' + [Guid]::NewGuid().ToString('N'))
$target = Join-Path $work '.agents\skills'
New-Item -ItemType Directory -Path $work | Out-Null
$env:ZSETUP_BIN = $zsetupPath
$env:KAI_SKILLS_RELEASE = '1.2.5'

function Invoke-Installer([string[]]$InstallerArguments, [int]$Expected = 0) {
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File (Join-Path $rootPath 'install.ps1') @InstallerArguments 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    if ($code -ne $Expected) {
        throw "installer exit $code, expected ${Expected}: $($output -join [Environment]::NewLine)"
    }
    return @($output)
}

try {
    $source = [IO.File]::ReadAllText((Join-Path $rootPath 'install.ps1'))
    if ($source -match '(?i)bash|git\.exe|node\.exe|npm\.cmd|npx\.cmd|jq\.exe') {
        throw 'native Windows installer contains a forbidden runtime dependency'
    }

    $plan = (Invoke-Installer -InstallerArguments @('-Action','Plan','-Skill','kai-software','-Consumer','codex',
        '-Scope','user','-TargetSkills',$target)) -join "`n" | ConvertFrom-Json
    if ($plan.status -ne 'planned' -or $plan.packages.Count -ne 1 -or
        $plan.destination -ne $target) { throw 'single-skill plan mismatch' }

    Invoke-Installer -InstallerArguments @('-Action','Install','-Skill','kai-software','-Consumer','codex',
        '-Scope','user','-TargetSkills',$target) | Out-Null
    if (-not (Test-Path -LiteralPath (Join-Path $target 'kai-software\SKILL.md') -PathType Leaf)) {
        throw 'single skill was not installed'
    }
    Invoke-Installer -InstallerArguments @('-Action','Install','-Skill','kai-software','-Consumer','codex',
        '-Scope','user','-TargetSkills',$target) | Out-Null

    $systemPlan = (Invoke-Installer -InstallerArguments @('-Action','Plan','-Platform','windows','-All','-Mode','on-device',
        '-Consumer','codex','-Scope','user','-TargetSkills',$target)) -join "`n" | ConvertFrom-Json
    if ($systemPlan.packages.Count -ne 9) { throw 'Windows system lock is not the exact 9-skill collection' }
    Invoke-Installer -InstallerArguments @('-Action','Upgrade','-Platform','windows','-All','-Mode','on-device',
        '-Consumer','codex','-Scope','user','-TargetSkills',$target) | Out-Null

    $modified = Join-Path $target 'windows-system-diagnostics\SKILL.md'
    Add-Content -LiteralPath $modified -Value 'modified-by-native-test'
    Invoke-Installer -InstallerArguments @('-Action','Uninstall','-Platform','windows','-All','-Mode','on-device',
        '-Consumer','codex','-Scope','user','-TargetSkills',$target) -Expected 2 | Out-Null
    if (-not (Select-String -LiteralPath $modified -SimpleMatch 'modified-by-native-test' -Quiet)) {
        throw 'modified user content was not preserved'
    }
    Copy-Item -LiteralPath (Join-Path $rootPath 'skills\windows-system-diagnostics\SKILL.md') `
        -Destination $modified -Force
    Invoke-Installer -InstallerArguments @('-Action','Uninstall','-Platform','windows','-All','-Mode','on-device',
        '-Consumer','codex','-Scope','user','-TargetSkills',$target) | Out-Null
    if (-not (Test-Path -LiteralPath (Join-Path $target 'kai-software\SKILL.md'))) {
        throw 'shared single-skill ownership was removed with the system selection'
    }
    Invoke-Installer -InstallerArguments @('-Action','Uninstall','-Skill','kai-software','-Consumer','codex',
        '-Scope','user','-TargetSkills',$target) | Out-Null
    if (Get-ChildItem -LiteralPath $target -Directory | Where-Object Name -ne '.linkease-skills') {
        throw 'owned skills remain after final uninstall'
    }
    [ordered]@{status='passed';singleSkill=1;windowsSystem=9;destination=$target} |
        ConvertTo-Json -Compress
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
