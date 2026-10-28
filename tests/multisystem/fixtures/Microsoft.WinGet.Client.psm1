# External WinGet module protocol fixture. No Kai implementation is replaced.
function Record-Call($Operation, $Arguments) {
    @{operation=$Operation;arguments=$Arguments} | ConvertTo-Json -Depth 6 -Compress |
        Add-Content -LiteralPath $env:KAI_WINGET_FIXTURE_LOG -Encoding UTF8
}
function Read-State {
    Get-Content -LiteralPath $env:KAI_WINGET_FIXTURE_STATE -Raw | ConvertFrom-Json
}
function Find-WinGetPackage {
    [CmdletBinding()]param([string]$Id,[string[]]$Query,[string]$MatchOption,
        [ValidateSet('winget')][string]$Source,[uint32]$Count)
    Record-Call 'find' $PSBoundParameters
    $state=Read-State
    if ($state.catalogMode -eq 'missing') { return }
    if ($Id -and $Id -ne 'Example.Tree') { return }
    if ($state.catalogMode -eq 'incomplete') {
        return [pscustomobject]@{Id='Example.Tree';Name='Tree';Source=$null;Version=$null;AvailableVersions=@()}
    }
    if ($state.catalogMode -in @('null-versions','blank-versions')) {
        $versions=$null
        if ($state.catalogMode -eq 'blank-versions') { $versions=@('','   ') }
        return [pscustomobject]@{Id='Example.Tree';Name='Tree';Source=$null;Version=$null;AvailableVersions=$versions}
    }
    if ($state.catalogMode -eq 'wrong-source') {
        return [pscustomobject]@{Id='Example.Tree';Name='Wrong';Source='msstore';Version='2.0.0';AvailableVersions=@('2.0.0')}
    }
    if ($state.catalogMode -eq 'ambiguous') {
        [pscustomobject]@{Id='Example.Tree';Name='Duplicate';Source='winget';Version='2.0.0';AvailableVersions=@('2.0.0')}
    }
    [pscustomobject]@{Id='Example.Tree';Name='Tree 中文';Source='winget';Version='2.0.0';AvailableVersions=@('2.0.0','1.0.0')}
}
function Get-WinGetPackage {
    [CmdletBinding()]param([string]$Id,[string]$MatchOption,
        [ValidateSet('winget')][string]$Source,[uint32]$Count)
    Record-Call 'get' $PSBoundParameters
    $state=Read-State
    if ($state.installed) {
        [pscustomobject]@{Id='Example.Tree';Name='Tree 中文';Source='winget';InstalledVersion=$state.installed}
    }
}
function Install-WinGetPackage {
    [CmdletBinding(SupportsShouldProcess)]param([string]$Id,[string]$Version,[string]$MatchOption,
        [ValidateSet('winget')][string]$Source,[ValidateSet('Silent')][string]$Mode)
    Record-Call 'install' $PSBoundParameters
    $state=Read-State
    if ($state.failure) {
        return [pscustomobject]@{Status='InstallError';InstallerErrorCode=37;ExtendedErrorCode=@{HResult=-123};RebootRequired=$false}
    }
    $state.installed=$Version
    $state|ConvertTo-Json -Compress|Set-Content -LiteralPath $env:KAI_WINGET_FIXTURE_STATE -Encoding UTF8
    [pscustomobject]@{Status='Ok';InstallerErrorCode=0;ExtendedErrorCode=$null;RebootRequired=$false}
}
function Uninstall-WinGetPackage {
    [CmdletBinding(SupportsShouldProcess)]param([string]$Id,[string]$MatchOption,
        [ValidateSet('winget')][string]$Source,[ValidateSet('Silent')][string]$Mode)
    Record-Call 'remove' $PSBoundParameters
    $state=Read-State;$state.installed=''
    $state|ConvertTo-Json -Compress|Set-Content -LiteralPath $env:KAI_WINGET_FIXTURE_STATE -Encoding UTF8
    [pscustomobject]@{Status='Ok';UninstallerErrorCode=0;ExtendedErrorCode=$null;RebootRequired=$false}
}
Export-ModuleMember -Function Find-WinGetPackage,Get-WinGetPackage,Install-WinGetPackage,Uninstall-WinGetPackage
