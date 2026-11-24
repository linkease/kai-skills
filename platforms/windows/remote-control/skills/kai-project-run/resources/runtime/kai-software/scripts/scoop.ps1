# PowerShell 5.1+; pinned zsetup Scoop ownership and ks-cli payload workflow.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

$script:SoftwareScriptRoot=$PSScriptRoot
# BEGIN OWNED MODULE HASHES
$softwareModules=[ordered]@{
    'scoop/client.ps1'='bc6505d224b66b10520636a110e90198369672394aa185eb3ec4b1256dc17f31'
    'scoop/identity.ps1'='de7a67154f1ad127383638d57ff750775620586ec3e2657f1448eee587a1d40e'
    'scoop/json.ps1'='25d66ab0adf1c4d1cc754187f6ca1b4ffedda1ead5c9dc9874a1ac9345d95f90'
    'scoop/packages.ps1'='0d71f68b1f293dd5f7906dfa1aa85c182fa2a3b85e501c50c71ade964f7ecc9c'
    'scoop/search.ps1'='6813081286af1bafc785b4f1d6c8e9729fb0c78d390be53bb264c1c96fc89470'
    'market.ps1'='f3c3acd04ba1daa9e8bfe2416765fddce63fce9eec9e33b9169d31d955beb748'
}
# END OWNED MODULE HASHES
foreach($member in $softwareModules.GetEnumerator()) {
    $path=Join-Path $script:SoftwareScriptRoot $member.Key
    $item=Get-Item -LiteralPath $path -Force
    if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $member.Value){throw 'Software module integrity mismatch'}
}
. (Join-Path $script:SoftwareScriptRoot 'scoop/json.ps1')
. (Join-Path $script:SoftwareScriptRoot 'scoop/identity.ps1')
. (Join-Path $script:SoftwareScriptRoot 'scoop/client.ps1')
. (Join-Path $script:SoftwareScriptRoot 'scoop/packages.ps1')
. (Join-Path $script:SoftwareScriptRoot 'scoop/search.ps1')

try {
    $request = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $action = [string]$request.action; $subject = [string]$request.subject; $version = [string]$request.version
    if ($action -notin @('probe','setup','search','info','install','remove','refresh','files','plan','inventory','catalog','recovery','apply')) { Fail 2 'usage' 'Unknown Scoop software operation.' }
    $script:policy = [string]$request.policy; if (!$script:policy) { $script:policy = 'auto' }
    if ($script:policy -notin @('required','auto','none')) { Fail 2 'usage' 'Select required, auto or none.' }
    $script:architecture = Resolve-Architecture
    $root = Scoop-Root; $lock = Read-Lock
    $env:SCOOP = $root; $env:Path = (Join-Path $root 'shims') + [IO.Path]::PathSeparator + $env:Path
    if ($action -in @('probe','plan','inventory','catalog','recovery','apply')) { . (Join-Path $PSScriptRoot 'market.ps1'); Invoke-Market; exit 0 }
    if ($action -eq 'probe') {
        $owned = Test-OwnedScoop $root $lock
        $zsetupPath = [string]$env:KAI_ZSETUP_BIN
        $ksCliPath = [string]$env:KAI_KSCLI_BIN
        $zsetupReady = ($zsetupPath -and (Test-Path -LiteralPath $zsetupPath -PathType Leaf)) -or $null -ne (Get-Command zsetup.exe -ErrorAction SilentlyContinue) -or $null -ne (Get-Command zsetup -ErrorAction SilentlyContinue)
        $ksCliReady = ($ksCliPath -and (Test-Path -LiteralPath $ksCliPath -PathType Leaf)) -or $null -ne (Get-Command ks-cli.exe -ErrorAction SilentlyContinue) -or $null -ne (Get-Command ks-cli -ErrorAction SilentlyContinue)
        $installedCount = 0
        if ($owned) {
            $installedCount = @(Get-ChildItem -LiteralPath (Join-Path $root 'apps') -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -cne 'scoop' }).Count
        }
        $status = $(if (!$owned) {'absent'} elseif (!$ksCliReady) {'degraded'} else {'ready'})
        $dependencies = @(
            [ordered]@{id='zsetup';state=$(if ($zsetupReady) {'ready'} else {'missing'});detail='Owns the locked Scoop installation'},
            [ordered]@{id='scoop';state=$(if ($owned) {'ready'} else {'missing'});detail='Locked zsetup receipt and runtime'},
            [ordered]@{id='ks-cli';state=$(if ($ksCliReady) {'ready'} else {'missing'});detail='Managed payload workflow and receipt'},
            [ordered]@{id='kspeeder';state='optional';detail='Optional authorized acceleration gateway'}
        )
        Emit ([ordered]@{schemaVersion=1;status=$status;platform='windows';provider='scoop';root=$root;cache=(Join-Path $root 'cache');installedCount=$installedCount;dependencies=$dependencies;evidenceTime=[DateTime]::UtcNow.ToString('o')})
        exit 0
    }
    if ($action -eq 'setup') {
        $runtimeState = Assert-KSpeederRuntimeStarted
        $null = Ensure-OwnedScoop $root $lock
        Emit ([ordered]@{schemaVersion=1;status='passed';operation='windows-essentials-setup';
            scoop=[ordered]@{state='ready';root=$root};ksCli=[ordered]@{state='ready'};kspeeder=$runtimeState;
            evidenceTime=[DateTime]::UtcNow.ToString('o')})
        exit 0
    }
    if ($action -eq 'search') {
        if (!$subject -or $subject.StartsWith('-') -or $subject.Length -gt 256) { Fail 2 'usage' 'Supply a bounded literal search term.' }
        if (!(Test-OwnedScoop $root $lock)) { Emit @(); exit 0 }
        $searchLimit=3
        if($null -ne $request.searchLimit){$searchLimit=[int]$request.searchLimit}
        if($searchLimit -lt 1 -or $searchLimit -gt 11){Fail 2 'usage' 'Invalid internal search bound.'}
        $rows=@(Scoop-Search $root $subject $searchLimit)
        Emit @($rows); exit 0
    }
    if ($action -eq 'install') { $null = Ensure-OwnedScoop $root $lock; Invoke-Install $root $subject $version; exit 0 }
    if (!(Test-OwnedScoop $root $lock)) { Fail 11 'invalid-provider-receipt' 'Scoop is not owned by the exact locked zsetup M6 installation.' }
    if ($action -eq 'refresh') {
        $parts = Parse-Identity $subject -BucketOnly
        $output = Invoke-KsCli @('scoop','bucket','update','--policy',$script:policy,$parts[0]) @('route.git-github.v1')
        $receipt = $null
        foreach ($candidate in @(Json-Objects ($output -join "`n"))) { if ($candidate.operation -eq 'bucket-update') { $receipt = $candidate } }
        if ($null -eq $receipt -or $receipt.status -ne 'passed' -or $receipt.bucket -cne $parts[0] -or $receipt.acceleration_policy -cne $script:policy -or $receipt.global_git_config_changed -ne $false -or $receipt.remote_url_changed -ne $false) {
            Fail 11 'invalid-provider-receipt' 'ks-cli returned a mismatched bucket update receipt.' $receipt
        }
        Emit @{schemaVersion=1;status='passed';operation='refresh';provider='scoop';bucket=$parts[0];nativeReceipt=$receipt;exitCode=0}; exit 0
    }
    $parts = Parse-Identity $subject
    if ($action -eq 'info') { Emit (Scoop-Info $root $parts[0] $parts[1]); exit 0 }
    if ($action -eq 'files') { Invoke-Files $root $subject; exit 0 }
    if ($action -eq 'remove') { Invoke-Remove $root $subject; exit 0 }
} catch {
    Fail 11 'provider-failed' $_.Exception.Message
}
