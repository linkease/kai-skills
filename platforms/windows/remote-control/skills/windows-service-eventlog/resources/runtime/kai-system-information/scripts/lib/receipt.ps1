# Dot-source only: result construction does not perform observations or authorize execution.
function Add-Fact([string]$Name, $Value, [string]$Source, [string]$Status='observed') {
    $script:facts[$Name] = $Value
    [void]$script:evidence.Add([ordered]@{
        id = 'fact-' + ($script:evidence.Count+1); source = $Source; status = $Status
        observedAt = $script:now; factPaths = @('/facts/'+$Name)
    })
}
function Add-Error([string]$Code,[string]$Message) {
    [void]$script:errors.Add(@{code=$Code;message=$Message})
    if ($script:operationStatus -ne 'failed') { $script:operationStatus='partial' }
}

function Write-Observation([string]$OperationName, [bool]$ReadOnly=$true, $Effects=$null, $Verification=$null) {
if($ReadOnly -or $null -eq $Effects){$Effects=@{requested=@();completed=@();unknown=@();remaining=@()}}
if($null -eq $Verification){$Verification=@{status='not_required';checks=@()}}
$result=[ordered]@{
    schemaVersion=1;operation=$OperationName;operationStatus=$operationStatus;targetId=$TargetId
    readOnly=$ReadOnly;observedAt=$now;facts=$facts;evidence=@($evidence.ToArray())
    effects=$Effects
    verification=$Verification;errors=@($errors.ToArray());truncated=$false
}
$json=$result | ConvertTo-Json -Depth 24 -Compress
if ($utf8.GetByteCount($json) -gt 8192) {
    $result.operationStatus='failed';$result.facts=@{};$result.evidence=@()
    $result.errors=@(@{code='RESULT_LIMIT';message='Selected facts exceed the default byte limit; query fewer sections.'})
    $json=$result | ConvertTo-Json -Depth 24 -Compress
}
[Console]::WriteLine($json)
return ($result.operationStatus -eq 'succeeded')

}
