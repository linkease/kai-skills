function Invoke-Install([string]$Root, [string]$Target, [string]$Version) {
    $parts = Parse-Identity $Target
    $before = Scoop-Info $Root $parts[0] $parts[1]
    if ($Version -and [string]$before.availableVersion -cne $Version) { Fail 4 'version-unavailable' 'Requested exact version differs from the pinned Scoop manifest.' }
    $receiptRoot = Join-Path ([IO.Path]::GetTempPath()) ('kai-scoop-receipt-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $receiptRoot | Out-Null
    $receiptPath = Join-Path $receiptRoot 'receipt.json'
    try {
        $null = Invoke-KsCli @('scoop','install','--architecture',$script:architecture,'--policy',$script:policy,'--receipt',$receiptPath,$Target) @('download-gateway.v1','route.github-release.v1')
        if (!(Test-Path -LiteralPath $receiptPath -PathType Leaf)) { Fail 11 'invalid-provider-receipt' 'ks-cli did not create the requested Scoop receipt.' }
        try { $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json } catch { Fail 11 'invalid-provider-receipt' 'The Scoop receipt is not JSON.' }
        Assert-PayloadReceipt $receipt 'install' $Target
        $result = Scoop-Info $Root $parts[0] $parts[1]
        if (!$result.installed -or [string]$result.installedVersion -cne [string]$result.availableVersion) { Fail 11 'version-mismatch' 'Scoop installation state differs from its manifest.' }
        $result['nativeReceipt'] = $receipt
        Emit $result
    } finally { Remove-Item -LiteralPath $receiptRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

function Invoke-Remove([string]$Root, [string]$Target) {
    $parts = Parse-Identity $Target
    $manifest = Manifest $Root $parts[0] $parts[1]
    $appRoot = Join-Path $Root ('apps\' + $parts[1])
    if (!(Test-Path -LiteralPath $appRoot -PathType Container)) {
        Emit @{schemaVersion=1;status='passed';operation='remove';id=('scoop:'+$Target);reused=$true;exitCode=0}; return
    }
    $xdg = Join-Path ([IO.Path]::GetTempPath()) ('kai-scoop-config-' + [Guid]::NewGuid().ToString('N'))
    $config = Join-Path $xdg 'scoop'; New-Item -ItemType Directory -Path $config | Out-Null
    [IO.File]::WriteAllText((Join-Path $config 'config.json'), '{"no_junction":true,"use_lessmsi":true}', (New-Object Text.UTF8Encoding($false)))
    $previous = $env:XDG_CONFIG_HOME; $env:XDG_CONFIG_HOME = $xdg
    try {
        # scoop.cmd prefers pwsh when it is on PATH. That makes `scoop uninstall pwsh`
        # run inside the package being removed, so Scoop refuses the uninstall but
        # still exits zero. Pin the inbox Windows PowerShell host for every removal.
        $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $scoopScript = Join-Path $Root 'apps\scoop\current\bin\scoop.ps1'
        Assert-Leaf $windowsPowerShell 'Windows PowerShell'
        Assert-Leaf $scoopScript 'Scoop core script'
        $native = Invoke-NativeCaptured $windowsPowerShell @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$scoopScript,'uninstall',$parts[1])
        if ($native.exitCode -ne 0) { Fail $native.exitCode 'native-package-failed' 'Native Scoop uninstall failed.' @{exitCode=$native.exitCode;output=($native.output -join "`n")} }
    } finally { $env:XDG_CONFIG_HOME = $previous; Remove-Item -LiteralPath $xdg -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $appRoot) { Fail 11 'remove-incomplete' 'Scoop app directory remains after uninstall.' }
    foreach ($bin in @(Bin-Records $manifest)) { foreach ($extension in @('.exe','.cmd','.ps1')) {
        if (Test-Path -LiteralPath (Join-Path $Root ('shims\'+$bin.alias+$extension))) { Fail 11 'remove-incomplete' 'A Scoop shim remains after uninstall.' }
    } }
    Emit @{schemaVersion=1;status='passed';operation='remove';id=('scoop:'+$Target);exitCode=0}
}

function Invoke-Files([string]$Root, [string]$Target) {
    $parts = Parse-Identity $Target; $info = Scoop-Info $Root $parts[0] $parts[1]
    if (!$info.installed) { Fail 4 'not-installed' 'The selected Scoop application is not installed.' }
    $base = Join-Path $Root ("apps\$($parts[1])\$($info.installedVersion)")
    $files = @(); $queue = New-Object Collections.Queue; $queue.Enqueue($base)
    while ($queue.Count -gt 0) {
        $directory = [string]$queue.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            $files += $item.FullName
            if ($item.PSIsContainer -and !($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $queue.Enqueue($item.FullName) }
        }
    }
    Emit @{schemaVersion=1;status='passed';operation='files';id=('scoop:'+$Target);files=@($files);exitCode=0}
}
