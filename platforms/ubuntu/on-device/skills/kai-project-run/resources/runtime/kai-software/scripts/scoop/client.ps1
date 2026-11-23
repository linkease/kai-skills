function KsCli {
    $client = [string]$request.ksCli
    if (!$client) { $client = $env:KAI_KSCLI_BIN }
    Assert-Leaf $client 'ks-cli'
    return $client
}

function Invoke-KsCli([string[]]$Arguments, [string[]]$Capabilities) {
    $client = KsCli
    $runtime = [string]$request.runtimeBinary
    $identity = [string]$request.runtimeIdentity
    if (($runtime -and !$identity) -or ($identity -and !$runtime)) { Fail 2 'usage' 'Runtime binary and identity must be supplied together.' }
    $command = @('--json') + $Arguments
    if ($script:policy -eq 'required' -and $runtime) {
        Assert-Leaf $runtime 'KSpeeder runtime binary'; Assert-Leaf $identity 'KSpeeder runtime identity'
        $wrapper = @('--json','runtime','exec','--service-binary',$runtime,'--identity',$identity)
        foreach ($capability in $Capabilities) { $wrapper += @('--require-capability',$capability) }
        $command = $wrapper + @('--',$client) + $command
    }
    $native = Invoke-NativeCaptured $client $command
    if ($native.exitCode -ne 0) { Fail $native.exitCode 'native-package-failed' 'ks-cli Scoop workflow failed.' @{exitCode=$native.exitCode;output=($native.output -join "`n")} }
    return @($native.output)
}

function Assert-KSpeederRuntimeStarted {
    $client = KsCli
    $runtime = [string]$request.runtimeBinary
    $identity = [string]$request.runtimeIdentity
    Assert-Leaf $runtime 'KSpeeder runtime binary'; Assert-Leaf $identity 'KSpeeder runtime identity'
    $native = Invoke-NativeCaptured $client @('--json','runtime','exec','--service-binary',$runtime,'--identity',$identity,
        '--require-capability','download-gateway.v1','--require-capability','route.github-release.v1','--',$client,'--version')
    if ($native.exitCode -ne 0) { Fail $native.exitCode 'kspeeder-start-failed' 'KSpeeder runtime did not start with the required capabilities.' @{exitCode=$native.exitCode;output=($native.output -join "`n")} }
    return [ordered]@{state='started';mode='task-scoped';capabilities=@('download-gateway.v1','route.github-release.v1')}
}

function Assert-PayloadReceipt($Receipt, [string]$Operation, [string]$Target) {
    if ($Receipt.schema_version -ne 1 -or [string]$Receipt.status -cne 'passed' -or [string]$Receipt.tool -cne 'scoop' -or
        [string]$Receipt.operation -cne $Operation -or [string]$Receipt.target -cne $Target -or
        [string]$Receipt.architecture -cne $script:architecture -or [string]$Receipt.bucket_commit -notmatch '^[0-9a-f]{40}$' -or
        [string]$Receipt.acceleration_policy -cne $script:policy -or $Receipt.native_exit_code -ne 0 -or
        [string]$Receipt.integrity -cne 'manifest-hash-and-native-scoop' -or @($Receipt.packages).Count -lt 1 -or
        $Receipt.system_proxy_changed -ne $false -or $Receipt.global_git_config_changed -ne $false) {
        Fail 11 'invalid-provider-receipt' 'ks-cli returned a mismatched Scoop receipt.' $Receipt
    }
    $targetFound = $false
    foreach ($package in @($Receipt.packages)) {
        if ([string]$package.identity -ceq $Target) { $targetFound = $true }
        if ([string]$package.identity -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$' -or
            [string]::IsNullOrWhiteSpace([string]$package.version) -or @($package.payloads).Count -lt 1) {
            Fail 11 'invalid-provider-receipt' 'A Scoop package receipt is incomplete.' $Receipt
        }
        foreach ($payload in @($package.payloads)) {
            if ([string]::IsNullOrWhiteSpace([string]$payload.id) -or [string]::IsNullOrWhiteSpace([string]$payload.selected) -or
                [long]$payload.bytes -lt 0) {
                Fail 11 'invalid-provider-receipt' 'A Scoop payload receipt is incomplete.' $Receipt
            }
            if ($script:policy -eq 'required' -and
                (!([string]$payload.selected).StartsWith('admin_proxy') -or $payload.hash_verified -ne $true -or $payload.cache_seeded -ne $true)) {
                Fail 11 'invalid-provider-receipt' 'Required Scoop payload acceleration was not proven.' $Receipt
            }
            if ($script:policy -eq 'none' -and
                ([string]$payload.selected -cne 'not-applied' -or [long]$payload.bytes -ne 0 -or
                    $payload.hash_verified -ne $false -or $payload.cache_seeded -ne $false)) {
                Fail 11 'invalid-provider-receipt' 'None policy receipt incorrectly claims a payload transfer.' $Receipt
            }
        }
    }
    if (!$targetFound) { Fail 11 'invalid-provider-receipt' 'The Scoop receipt does not contain the requested package.' $Receipt }
}
