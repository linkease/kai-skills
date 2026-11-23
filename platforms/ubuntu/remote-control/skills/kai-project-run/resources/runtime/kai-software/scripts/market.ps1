$script:SoftwareScriptRoot=$PSScriptRoot
$script:SoftwareBootstrapScript=Join-Path $PSScriptRoot '../../kai-tool-bootstrap/resources/bootstrap-windows.ps1'
# BEGIN OWNED MODULE HASHES
$softwareModules=[ordered]@{
    'market/dispatch.ps1'='699adb75a9d6d680f955ae21c431e68481bee792deca7ba6afe685b395863ccc'
    'market/inventory.ps1'='90638d15a746a0ac3b6e7b2f8c62f34f491c648387a9b99d31829f506ae96a19'
    'market/packages.ps1'='685f8ba07670983f22140e56eef05d47ab53ef361d817ce7d021a293a16ad59e'
    'market/plan.ps1'='e74eda1b3505138a9591ab31f3eb3b71beb377e20796d0c0d5f74be5a63f1249'
    'market/setup.ps1'='1ff7337c244237ef19703d7ce681fa97294302f30752e3d2396a95c245b0b1dd'
    'market/sources.ps1'='d12480b635b30d5ffae169d95c2cdd417bb926afdc1e1ba726f3ecc9603d0ff1'
}
# END OWNED MODULE HASHES
foreach($member in $softwareModules.GetEnumerator()) {
    $path=Join-Path $script:SoftwareScriptRoot $member.Key
    $item=Get-Item -LiteralPath $path -Force
    if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $member.Value){throw 'Software module integrity mismatch'}
}
. (Join-Path $script:SoftwareScriptRoot 'market/sources.ps1')
. (Join-Path $script:SoftwareScriptRoot 'market/packages.ps1')
. (Join-Path $script:SoftwareScriptRoot 'market/inventory.ps1')
. (Join-Path $script:SoftwareScriptRoot 'market/plan.ps1')
. (Join-Path $script:SoftwareScriptRoot 'market/setup.ps1')
. (Join-Path $script:SoftwareScriptRoot 'market/dispatch.ps1')
