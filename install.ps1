param(
    [ValidateSet('Plan','Install','Upgrade','Uninstall')][string]$Action = 'Plan',
    [string]$Skill,
    [string]$Bundle,
    [switch]$All,
    [ValidateSet('windows')][string]$Platform,
    [ValidateSet('on-device')][string]$Mode,
    [ValidateSet('codex','claude','opencode')][string]$Consumer = 'codex',
    [ValidateSet('user','project')][string]$Scope = 'user',
    [string]$TargetSkills,
    [string]$Architecture,
    [switch]$UpdateShared
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

function Fail([string]$Message) { throw $Message }
function Test-SafeId([string]$Value) { return $Value -cmatch '^[a-z0-9][a-z0-9-]{0,63}$' }
function ConvertTo-Map($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $map = @{}
        foreach ($property in $Value.PSObject.Properties) { $map[$property.Name] = ConvertTo-Map $property.Value }
        return $map
    }
    if ($Value -is [Array]) { return @($Value | ForEach-Object { ConvertTo-Map $_ }) }
    return $Value
}
function Read-JsonMap([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Fail "missing JSON file: $Path" }
    $file = Get-Item -LiteralPath $Path -Force
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $file.Length -gt 1048576) { Fail "unsafe JSON file: $Path" }
    return ConvertTo-Map ([IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json)
}
function Get-TreeDigest([string]$Path) {
    if (-not $env:ZSETUP_BIN -or -not (Test-Path -LiteralPath $env:ZSETUP_BIN -PathType Leaf)) { Fail 'ZSETUP_BIN is required' }
    $value = (& $env:ZSETUP_BIN 'checksum-tree' $Path 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $value -cnotmatch '^sha256:[0-9a-f]{64}$') { Fail "cannot verify package tree: $Path" }
    return $value
}
function Test-Reparse([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return (((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}
function Get-References([hashtable]$Selections) {
    $references = @{}
    foreach ($record in $Selections.Values) { foreach ($member in @($record.members)) { $references[$member.id] = $true } }
    return $references
}
function Test-SameMembers($Left, $Right) {
    $a = @($Left | ForEach-Object { "$($_.id)|$($_.version)|$($_.treeDigest)" })
    $b = @($Right | ForEach-Object { "$($_.id)|$($_.version)|$($_.treeDigest)" })
    return (($a -join "`n") -ceq ($b -join "`n"))
}
function Remove-Tree([string]$Path) { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force } }

try {
    $selectionCount = 0
    if ($Skill) { $selectionCount++ }
    if ($Bundle) { $selectionCount++ }
    if ($All) { $selectionCount++ }
    if ($selectionCount -ne 1) { Fail 'select exactly one Skill, Bundle or platform All' }
    foreach ($identity in @($Skill,$Bundle)) { if ($identity -and -not (Test-SafeId $identity)) { Fail 'invalid selection identity' } }
    if ($All -and ($Platform -ne 'windows' -or $Mode -ne 'on-device')) { Fail 'Windows All requires Platform windows and Mode on-device' }
    if ($Architecture -and $Architecture -notin @('x86_64','amd64','i686')) { Fail 'unsupported Windows architecture' }
    if ($UpdateShared -and $Action -ne 'Upgrade') { Fail 'UpdateShared requires Upgrade' }

    $root = $PSScriptRoot
    $catalog = Read-JsonMap (Join-Path $root 'business-catalog.json')
    if ($catalog.schemaVersion -ne 1 -or $catalog.defaultPolicy.installAll -ne $false) { Fail 'invalid business catalog' }
    $byId = @{}
    foreach ($package in @($catalog.skills)) {
        if (-not (Test-SafeId $package.id) -or $byId.ContainsKey($package.id) -or $package.path -cne "skills/$($package.id)" -or $package.treeDigest -cnotmatch '^sha256:[0-9a-f]{64}$') { Fail 'unsafe package record' }
        $byId[$package.id] = $package
    }
    if ($Skill) {
        if (-not $byId.ContainsKey($Skill)) { Fail 'unknown skill' }
        $requested = @($byId[$Skill]); $selection = "skill:$Skill"
    } else {
        $name = $Bundle
        if ($All) { $name = 'windows-all-on-device' }
        $lock = Read-JsonMap (Join-Path $root "bundles/$name.json")
        $requested = @()
        foreach ($member in @($lock.members)) {
            if (-not $byId.ContainsKey($member.id)) { Fail 'collection member is unavailable' }
            $package = $byId[$member.id]
            if ($package.version -cne $member.version -or $package.treeDigest -cne $member.treeDigest) { Fail 'collection member digest mismatch' }
            $requested += $package
        }
        $selection = if ($All) { 'system:windows:on-device' } else { "bundle:$Bundle" }
    }
    foreach ($package in $requested) {
        if (@($package.platforms) -cnotcontains 'windows') { Fail "skill $($package.id) is not Windows-compatible" }
        $source = Join-Path $root ($package.path.Replace('/','\'))
        if (Test-Reparse $source) { Fail "package source is aliased: $($package.id)" }
        if ((Get-TreeDigest $source) -cne $package.treeDigest) { Fail "package source digest mismatch: $($package.id)" }
    }
    if (-not $TargetSkills) {
        if ($Scope -eq 'project') {
            $project = $env:KAI_SKILLS_PROJECT_ROOT; if (-not $project) { $project = (Get-Location).Path }
            $TargetSkills = switch ($Consumer) { codex { Join-Path $project '.agents\skills' }; claude { Join-Path $project '.claude\skills' }; opencode { Join-Path $project '.opencode\skills' } }
        } else {
            $TargetSkills = switch ($Consumer) {
                codex { Join-Path $HOME '.agents\skills' }
                claude { Join-Path $HOME '.claude\skills' }
                opencode { $config = $env:XDG_CONFIG_HOME; if (-not $config) { $config = Join-Path $HOME '.config' }; Join-Path $config 'opencode\skills' }
            }
        }
    }
    $target = [IO.Path]::GetFullPath($TargetSkills); $sourceRoot = [IO.Path]::GetFullPath($root)
    if ([IO.Path]::GetPathRoot($target) -ceq $target -or $target.TrimEnd('\') -ceq $sourceRoot.TrimEnd('\') -or $target.StartsWith($sourceRoot.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { Fail 'unsafe target skills directory' }
    if (Test-Reparse $target) { Fail 'target skills directory is a reparse point' }

    $stateDirectory = Join-Path $target '.linkease-skills'; $statePath = Join-Path $stateDirectory 'business-state.json'
    if ((Test-Reparse $stateDirectory) -or (Test-Reparse $statePath)) { Fail 'ownership state is aliased' }
    if (Test-Path -LiteralPath $statePath -PathType Leaf) { $state = Read-JsonMap $statePath } else { $state = @{schemaVersion=2;packages=@{};selections=@{}} }
    if ($state.schemaVersion -ne 2 -or $state.packages -isnot [hashtable] -or $state.selections -isnot [hashtable]) { Fail 'invalid ownership state' }
    $references = Get-References $state.selections
    foreach ($id in $state.packages.Keys) {
        if (-not (Test-SafeId $id) -or -not $references.ContainsKey($id)) { Fail 'invalid ownership relationship' }
        $record = $state.packages[$id]; $installed = Join-Path $target $id
        if ($record.treeDigest -cnotmatch '^sha256:[0-9a-f]{64}$' -or -not (Test-Path -LiteralPath $installed -PathType Container) -or (Test-Reparse $installed) -or (Get-TreeDigest $installed) -cne $record.treeDigest) { Fail "modified owned package is preserved: $id" }
    }

    $next = ConvertTo-Map (($state | ConvertTo-Json -Depth 20 -Compress) | ConvertFrom-Json)
    $requestedMembers = @($requested | ForEach-Object { @{id=$_.id;version=$_.version;treeDigest=$_.treeDigest} })
    if ($Action -eq 'Uninstall') {
        if ($next.selections.ContainsKey($selection)) { $next.selections.Remove($selection) }
    } else {
        if ($Action -eq 'Install' -and $next.selections.ContainsKey($selection) -and -not (Test-SameMembers $next.selections[$selection].members $requestedMembers)) { Fail 'selection changed; use Upgrade' }
        $next.selections[$selection] = @{consumer=$Consumer;scope=$Scope;release=$env:KAI_SKILLS_RELEASE;members=$requestedMembers}
        foreach ($package in $requested) {
            $existing = $state.packages[$package.id]
            if ($existing -and $existing.treeDigest -cne $package.treeDigest) {
                $other = @($state.selections.Keys | Where-Object { $_ -cne $selection -and @($state.selections[$_].members.id) -ccontains $package.id })
                if ($other.Count -gt 0 -and -not ($Action -eq 'Upgrade' -and $UpdateShared)) { Fail "shared package upgrade requires UpdateShared: $($package.id)" }
            }
            $next.packages[$package.id] = @{version=$package.version;treeDigest=$package.treeDigest;installMode='copy';sourcePath=(Join-Path $root ($package.path.Replace('/','\')))}
        }
    }
    $nextReferences = Get-References $next.selections; $removed = @()
    foreach ($id in @($next.packages.Keys)) { if (-not $nextReferences.ContainsKey($id)) { $next.packages.Remove($id); $removed += $id } }
    $replace = @()
    foreach ($package in $requested) {
        if ($Action -eq 'Uninstall') { continue }
        $existing = $state.packages[$package.id]; $installed = Join-Path $target $package.id
        if (-not $existing) { if (Test-Path -LiteralPath $installed) { Fail "unowned destination is preserved: $($package.id)" }; $replace += $package.id }
        elseif ($existing.treeDigest -cne $package.treeDigest) { $replace += $package.id }
    }
    $release = $env:KAI_SKILLS_RELEASE; if (-not $release) { $release = $catalog.version }
    $plan = [ordered]@{schemaVersion=1;status=if($Action -eq 'Plan'){'planned'}else{'ready'};selection=$selection;action=$Action.ToLowerInvariant();destination=$target;consumer=$Consumer;scope=$Scope;release=$release;packages=@($requestedMembers);removed=@($removed);programOperations=@();serviceOperations=$false}
    if ($Action -eq 'Plan') { $plan | ConvertTo-Json -Depth 10 -Compress; exit 0 }

    New-Item -ItemType Directory -Path $target -Force | Out-Null
    if (Test-Reparse $target) { Fail 'target became a reparse point' }
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    $lockPath = Join-Path $stateDirectory 'operation.lock'; $lock = $null
    $transaction = Join-Path ([IO.Path]::GetDirectoryName($target)) ('.kai-skills-' + [Guid]::NewGuid().ToString('N'))
    $newRoot = Join-Path $transaction 'new'; $backupRoot = Join-Path $transaction 'backup'
    $movedNew = @(); $movedOld = @(); $stateReplaced = $false
    try {
        $lock = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        New-Item -ItemType Directory -Path $newRoot,$backupRoot | Out-Null
        foreach ($id in $replace) { Copy-Item -LiteralPath (Join-Path $root "skills\$id") -Destination (Join-Path $newRoot $id) -Recurse; if ((Get-TreeDigest (Join-Path $newRoot $id)) -cne $next.packages[$id].treeDigest) { Fail "staged package digest mismatch: $id" } }
        foreach ($id in @($removed) + @($replace)) { $installed = Join-Path $target $id; if (Test-Path -LiteralPath $installed) { Move-Item -LiteralPath $installed -Destination (Join-Path $backupRoot $id); $movedOld += $id } }
        foreach ($id in $replace) { Move-Item -LiteralPath (Join-Path $newRoot $id) -Destination (Join-Path $target $id); $movedNew += $id }
        $stateTemporary = Join-Path $stateDirectory ('.business-state-' + [Guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::WriteAllText($stateTemporary,($next | ConvertTo-Json -Depth 20 -Compress) + "`n",(New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $statePath) { [IO.File]::Replace($stateTemporary,$statePath,(Join-Path $backupRoot 'business-state.json')) } else { [IO.File]::Move($stateTemporary,$statePath) }
        $stateReplaced = $true; Remove-Tree $transaction
    } catch {
        foreach ($id in $movedNew) { Remove-Tree (Join-Path $target $id) }
        foreach ($id in $movedOld) { $backup = Join-Path $backupRoot $id; if (Test-Path -LiteralPath $backup) { Move-Item -LiteralPath $backup -Destination (Join-Path $target $id) } }
        $stateBackup = Join-Path $backupRoot 'business-state.json'
        if ($stateReplaced -and (Test-Path -LiteralPath $stateBackup)) { Copy-Item -LiteralPath $stateBackup -Destination $statePath -Force }
        elseif ($stateReplaced -and $state.packages.Count -eq 0 -and $state.selections.Count -eq 0) { Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue }
        Remove-Tree $transaction; throw
    } finally {
        if ($lock) { $lock.Dispose() }
        Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    }
    $plan.status = 'succeeded'; $plan | ConvertTo-Json -Depth 10 -Compress; exit 0
} catch {
    [Console]::Error.WriteLine('kai-skills: ' + $_.Exception.Message)
    exit 2
}
