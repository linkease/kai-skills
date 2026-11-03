# PowerShell 5.1+; native catalog API and prepared ks-cli WinGet operations.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
function Emit($Value) {
    [Console]::Out.WriteLine((ConvertTo-Json -InputObject $Value -Depth 8 -Compress))
}
function Fail([int]$Code, [string]$Category, [string]$Reason, $NativeResult = $null) {
    Emit ([ordered]@{schemaVersion=1;status='failed';category=$Category;reason=$Reason;
        nativeResult=$NativeResult;exitCode=$Code})
    exit $Code
}
function Assert-CatalogAvailable($Package) {
    $versions = @($Package.AvailableVersions)
    # @($null) has one element. Failed native getters can yield null or blank
    # entries, so a count alone must not lead to Source's further network reads.
    $invalid = @($versions | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) })
    if ($versions.Count -eq 0 -or $invalid.Count -gt 0) {
        Fail 11 'catalog-unavailable' 'The native source returned an incomplete catalog. Inspect connectivity and explicitly refresh the winget source; no package operation was attempted.'
    }
}
function Exact-Catalog([string]$Id) {
    $items = @(Find-WinGetPackage -Id $Id -MatchOption Equals -Source winget -Count 2 -ErrorAction Stop)
    if ($items.Count -ne 1 -or $items[0].Id -cne $Id) {
        Fail 4 'no-unique-candidate' 'The selected source did not return exactly one matching package.'
    }
    Assert-CatalogAvailable $items[0]
    if ($items[0].Source -ne 'winget') { Fail 4 'source-mismatch' 'The package is not correlated to the selected source.' }
    return $items[0]
}
function Exact-Installed([string]$Id) {
    $items = @(Get-WinGetPackage -Id $Id -MatchOption Equals -Source winget -Count 2 -ErrorAction Stop)
    if ($items.Count -gt 1) { Fail 4 'ambiguous-installed-package' 'Preserve ambiguous installed entries.' }
    if ($items.Count -eq 1) {
        if ($items[0].Id -cne $Id -or $items[0].Source -ne 'winget') {
            Fail 4 'source-mismatch' 'The installed package is not correlated to the selected source.'
        }
        return $items[0]
    }
    return $null
}
function Package-Info($Catalog) {
    $installed = Exact-Installed $Catalog.Id
    $installedVersion = ''
    if ($null -ne $installed) { $installedVersion = [string]$installed.InstalledVersion }
    return [ordered]@{schemaVersion=1;id=('winget:'+$Catalog.Id);name=$Catalog.Id;
        displayName=$Catalog.Name;type='system-package';source='winget';manager='winget';
        platform='windows';compatible=$true;availableVersion=$Catalog.Version;
        availableVersions=@($Catalog.AvailableVersions);installedVersion=$installedVersion;
        installed=($installedVersion -ne '');entrypoint='';
        evidenceTime=[DateTime]::UtcNow.ToString('o');
        nextStep='Use the registered native application entry; WinGet does not expose a general file inventory.'}
}
function Invoke-PreparedWinGet([string[]]$NativeArguments, [string]$Operation) {
    $client = [string]$request.ksCli
    if (!$client) { $client = $env:KAI_KSCLI_BIN }
    if (!$client) {
        $command = Get-Command ks-cli.exe -CommandType Application -ErrorAction SilentlyContinue
        if ($command) { $client = $command.Source }
    }
    if (!$client -or !(Test-Path -LiteralPath $client -PathType Leaf)) {
        Fail 127 'missing-executable' 'Select an existing ks-cli for prepared WinGet operations.'
    }
    $output = @(& $client --json winget @NativeArguments)
    $code = $LASTEXITCODE
    $receipt = $null
    try { $receipt = ($output -join "`n") | ConvertFrom-Json } catch {}
    if ($code -ne 0) {
        $exitCode = 11
        if ($code -gt 0 -and $code -le 255) { $exitCode = $code }
        Fail $exitCode 'native-package-failed' 'Prepared WinGet failed; preserve the original native diagnostics.' @{exitCode=$code;receipt=$receipt}
    }
    if ($receipt -isnot [pscustomobject] -or $receipt.schema_version -ne 1 -or $receipt.status -ne 'passed' -or
        $receipt.system_proxy_changed -isnot [bool] -or
        $receipt.operation -ne $Operation -or $receipt.system_proxy_changed -ne $false) {
        Fail 11 'invalid-provider-receipt' 'ks-cli did not return a successful receipt for this operation.' $receipt
    }
    return $receipt
}
function Target-Architecture {
    $architecture = [string]$request.architecture
    if (!$architecture) { $architecture = $env:KAI_WINGET_ARCH }
    if (!$architecture) {
        switch ($env:PROCESSOR_ARCHITECTURE) {
            'AMD64' { $architecture = 'x64' }
            'ARM64' { $architecture = 'arm64' }
            'x86' { $architecture = 'x86' }
        }
    }
    if ($architecture -notin @('x64','arm64','x86')) { Fail 2 'usage' 'Select an explicit supported target architecture.' }
    return $architecture
}
try {
    $request = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $action = [string]$request.action
    $subject = [string]$request.subject
    $version = [string]$request.version
    if ($action -notin @('search','info','install','download','remove','refresh','files','owner')) {
        Fail 2 'usage' 'Unknown software operation.'
    }
    if ($action -eq 'refresh') {
        if ($subject -ne 'winget') { Fail 2 'usage' 'Explicitly select the winget source.' }
        $receipt = Invoke-PreparedWinGet @('source','update','--name','winget','--disable-interactivity') 'source-update'
        Emit @{schemaVersion=1;status='passed';operation='refresh';provider='winget';nativeResult=$receipt;exitCode=0}
        exit 0
    }
    if ($action -in @('files','owner')) { Fail 18 'unsupported-operation' 'WinGet exposes no general package file ownership API.' }
    if ($action -eq 'search') {
        if (!$subject -or $subject.StartsWith('-') -or $subject.Length -gt 512) {
            Fail 2 'usage' 'Supply a bounded literal search term.'
        }
    } elseif ($subject -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') {
        Fail 2 'usage' 'Use an exact source-qualified package identifier.'
    }
    if ($version -and ($version.Length -gt 128 -or $version -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$')) {
        Fail 2 'usage' 'Invalid exact package version.'
    }
    try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop }
    catch { Fail 18 'native-adapter-unavailable' 'Prepare a trusted Microsoft.WinGet.Client PowerShell module with its original manager; no automatic module installation.' }
    if ($action -eq 'search') {
        $packages = @(Find-WinGetPackage -Query @($subject) -Source winget -Count 3 -ErrorAction Stop)
        $rows = @()
        foreach ($package in ($packages | Select-Object -First 3)) {
            Assert-CatalogAvailable $package
            if ($package.Source -ne 'winget') { Fail 4 'source-mismatch' 'Search returned a different source.' }
            $row = Package-Info $package
            $row['matchReason'] = 'matched in the selected native provider catalog'
            $rows += $row
        }
        Emit $rows
        exit 0
    }
    if ($action -eq 'remove') {
        $installed = Exact-Installed $subject
        if ($null -eq $installed) {
            Emit @{schemaVersion=1;status='passed';operation='remove';id=('winget:'+$subject);reused=$true;exitCode=0}
            exit 0
        }
        $result = Uninstall-WinGetPackage -Id $subject -Source winget -MatchOption Equals -Mode Silent -Confirm:$false -ErrorAction Stop
    } else {
        $catalog = Exact-Catalog $subject
        $info = Package-Info $catalog
        if ($action -eq 'info') { Emit $info; exit 0 }
        $selected = [string]$catalog.Version
        if ($version) { $selected = $version }
        if (!$selected -or @($catalog.AvailableVersions) -cnotcontains $selected) {
            Fail 4 'version-unavailable' 'The exact version is absent from this provider catalog.'
        }
        if ($action -eq 'install' -and $info.installedVersion -ceq $selected) { Emit $info; exit 0 }
        $architecture = Target-Architecture
        if ($action -eq 'download') {
            $destination = [string]$request.destination
            if (!$destination -or $destination.Length -gt 2048 -or
                ![IO.Path]::IsPathRooted($destination) -or $destination.IndexOf([char]0) -ge 0) {
                Fail 2 'usage' 'Provide an absolute download directory.'
            }
            $prepared = Invoke-PreparedWinGet @('download','--id',$subject,'--exact','--version',$selected,
                '--architecture',$architecture,'--source','winget','--download-directory',$destination,
                '--disable-interactivity') 'download'
            Emit @{schemaVersion=1;status='passed';operation='download';id=('winget:'+$subject);
                version=$selected;architecture=$architecture;path=$destination;nativeResult=$prepared;exitCode=0}
            exit 0
        }
        $prepared = Invoke-PreparedWinGet @('install','--id',$subject,'--exact','--version',$selected,
            '--architecture',$architecture,'--source','winget','--silent','--disable-interactivity') 'install'
        $result = @{Status='Ok';RebootRequired=$null}
    }
    if ($null -eq $result -or $result.Status -ne 'Ok') {
        Fail 11 'native-package-failed' 'Inspect the original native result; no force, checksum bypass or installer override was used.' $result
    }
    if ($action -eq 'remove') {
        if ($null -ne (Exact-Installed $subject)) { Fail 11 'removal-verification-failed' 'The package is still registered after native removal.' }
        Emit @{schemaVersion=1;status='passed';operation='remove';id=('winget:'+$subject);rebootRequired=$result.RebootRequired;exitCode=0}
    } else {
        $info = Package-Info (Exact-Catalog $subject)
        if ($info.installedVersion -cne $selected) { Fail 11 'version-mismatch' 'The installed version differs from the selected exact version.' }
        $info['rebootRequired'] = $result.RebootRequired
        $info['nativeResult'] = $prepared
        Emit $info
    }
    exit 0
} catch {
    Fail 11 'native-provider-error' $_.Exception.Message @{hresult=$_.Exception.HResult;type=$_.Exception.GetType().FullName}
}
