param(
    [ValidateSet('Plan','Install','EnsureBash')][string]$Action = 'Plan',
    [string]$Skill,
    [string]$Bundle,
    [switch]$All,
    [ValidateSet('ubuntu','debian','istoreos','macos','windows')][string]$Platform,
    [ValidateSet('on-device','remote-control')][string]$Mode,
    [ValidateSet('codex','opencode','generic')][string]$Consumer = 'generic',
    [string]$TargetSkills,
    [string]$TrustedBash
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
trap {
    [ordered]@{schemaVersion=1;status='failed';reason=$_.Exception.Message;exitCode=2} | ConvertTo-Json -Compress
    exit 2
}
$count = 0
if ($Skill) { $count++ }
if ($Bundle) { $count++ }
if ($All) { $count++ }
if ($count -ne 1) { throw 'Select exactly one Skill, Bundle or platform All.' }
foreach ($id in @($Skill,$Bundle)) {
    if ($id -and $id -notmatch '^[a-z0-9][a-z0-9-]{0,63}$') { throw 'Invalid selection identity.' }
}
if ($All -and (!$Platform -or !$Mode)) { throw 'All requires Platform and Mode.' }
if ($Action -ne 'EnsureBash' -and $Consumer -eq 'generic' -and !$TargetSkills) { throw 'Specify TargetSkills for a generic consumer.' }
if ($Mode -eq 'remote-control' -and !$Platform) { throw 'Remote control requires Platform.' }
$catalog = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'business-catalog.json') | ConvertFrom-Json
if ($Skill) {
    $selected = @($catalog.skills | Where-Object { $_.id -ceq $Skill })
    if ($selected.Count -ne 1) { throw 'Unknown skill.' }
} else {
    $name = $Bundle
    if ($All) { $name = "$Platform-all-$Mode" }
    $lock = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "bundles/$name.json") | ConvertFrom-Json
    $selected = @($lock.members)
}
$packages = @()
foreach ($member in $selected) {
    $package = @($catalog.skills | Where-Object { $_.id -ceq $member.id })
    if ($package.Count -ne 1) { throw 'Missing catalog member.' }
    if ($member.treeDigest -and $member.treeDigest -cne $package[0].treeDigest) { throw 'Collection content mismatch.' }
    if ($member.version -and $member.version -cne $package[0].version) { throw 'Collection version mismatch.' }
    if ($Platform -and $package[0].platforms -cnotcontains $Platform) { throw 'Skill is incompatible with target platform.' }
    $packages += $package[0]
}
if ($Mode -eq 'remote-control') {
    $packages += @($catalog.skills | Where-Object { $_.kind -eq 'transport' -and $_.platforms -ccontains $Platform })
}
$selected = @($packages | Sort-Object -Property id -Unique)
# An offline business collection embeds bootstrap inside its members. Search only
# the selected packages first; distribution-level support is the fallback.
$bootstrap = $null
foreach ($package in $selected) {
    foreach ($relative in @('scripts/bootstrap-bash.ps1','resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1')) {
        $candidate = Join-Path $PSScriptRoot ("skills/" + $package.id + "/" + $relative)
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $bootstrap = $candidate; break }
    }
    if ($bootstrap) { break }
}
if (!$bootstrap) {
    foreach ($relative in @('tools/bootstrap-bash.ps1','skills/kai-tool-bootstrap/scripts/bootstrap-bash.ps1')) {
        $candidate = Join-Path $PSScriptRoot $relative
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $bootstrap = $candidate; break }
    }
}
if (!$TargetSkills) {
    if ($Consumer -eq 'codex') {
        $codexRoot = $env:CODEX_HOME
        if (!$codexRoot) { $codexRoot = Join-Path $HOME '.codex' }
        $TargetSkills = Join-Path $codexRoot 'skills'
    } elseif ($Consumer -eq 'opencode') {
        $configRoot = $env:XDG_CONFIG_HOME
        if (!$configRoot) { $configRoot = Join-Path $HOME '.config' }
        $TargetSkills = Join-Path $configRoot 'opencode/skills'
    }
}
if ($Action -eq 'Plan' -and !$TrustedBash) {
    [ordered]@{schemaVersion=1;status='planned';packages=@($selected | ForEach-Object { $_.id });
        destination=$TargetSkills;bootstrap=$bootstrap;nextStep='Use the native bootstrap Plan, then EnsureBash if needed; supply its trusted Bash path for managed installation.';
        programOperations=@();serviceOperations=$false;exitCode=0} | ConvertTo-Json -Depth 6 -Compress
    exit 0
}
if (!$bootstrap) { throw 'This selection has no Bash bootstrap; use the shell installer through your existing trusted Bash.' }
$nativePowerShell = (Get-Process -Id $PID).Path
$arguments = @('-NoLogo','-NoProfile','-NonInteractive','-File',$bootstrap,'-Action','Probe')
if ($Action -eq 'EnsureBash') { $arguments[$arguments.Length-1] = 'Ensure' }
if ($TrustedBash) { $arguments += @('-TrustedPath',$TrustedBash) }
$result = & $nativePowerShell @arguments
$code = $LASTEXITCODE
if ($code -ne 0) { [Console]::Out.WriteLine(($result | Out-String)); exit $code }
$bash = ($result | Out-String | ConvertFrom-Json).path
if (!$bash) { throw 'No verified Bash; use native bootstrap Plan/Ensure first.' }
if ($Action -eq 'EnsureBash') { [Console]::Out.WriteLine(($result | Out-String)); exit 0 }
$arguments = @((Join-Path $PSScriptRoot 'install.sh').Replace('\','/'))
if ($Skill) { $arguments += @('--skill',$Skill) }
if ($Bundle) { $arguments += @('--bundle',$Bundle) }
if ($All) { $arguments += '--all' }
if ($Platform) { $arguments += @('--platform',$Platform) }
if ($Mode) { $arguments += @('--mode',$Mode) }
$arguments += @('--consumer',$Consumer,'--json')
if ($TargetSkills) { $arguments += @('--target-skills',$TargetSkills) }
if ($Action -eq 'Plan') { $arguments += '--dry-run' }
& $bash @arguments
exit $LASTEXITCODE
