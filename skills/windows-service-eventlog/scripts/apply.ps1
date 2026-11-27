[CmdletBinding()]
param(
 [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$ServiceName,
 [Parameter(Mandatory)][ValidateSet('Start','Stop','Restart')][string]$Action,
 [Parameter(Mandatory)][ValidateSet('Running','Stopped','Paused')][string]$ExpectedStatus,
 [string]$TargetId=$(if($env:ZSETUP_TASK_TARGET_ID){$env:ZSETUP_TASK_TARGET_ID}else{'local'})
)
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false);[Console]::OutputEncoding=$utf8
$now=[DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$facts=[ordered]@{};$evidence=New-Object Collections.ArrayList;$errors=New-Object Collections.ArrayList;$operationStatus='failed'
$library=Join-Path $PSScriptRoot '../resources/runtime/kai-system-information/scripts/lib/receipt.ps1'
if(!(Test-Path -LiteralPath $library)){$library=Join-Path $PSScriptRoot '../../../../common/skills/kai-system-information/scripts/lib/receipt.ps1'}
if(!(Test-Path -LiteralPath $library)){$library=Join-Path $PSScriptRoot '../../../../../system-packs/common/skills/kai-system-information/scripts/lib/receipt.ps1'}
. $library
$requested=@(@{id='service-command';kind='native-scm-action';target=($ServiceName+':'+$Action)})
$effects=@{requested=$requested;completed=@();unknown=@();remaining=$requested}
$verification=@{status='not_run';checks=@()}
try {
 $bound=if($env:ZSETUP_TASK_TARGET_ID){$env:ZSETUP_TASK_TARGET_ID}else{'local'}
 if(!$TargetId -or $TargetId -cne $bound){throw 'TARGET_MISMATCH'}
 if($env:TARGET_CHANGE_APPROVED -ne 'YES'){throw 'AUTHORIZATION_REQUIRED'}
 $service=Get-Service -Name $ServiceName -ErrorAction Stop
 if([string]$service.Status -cne $ExpectedStatus){throw 'PRECONDITION_CHANGED'}
 Add-Fact previousState ([string]$service.Status) 'native SCM state compared with the explicit precondition'
 $effects.remaining=@();$effects.unknown=$requested;$operationStatus='unknown'
 switch($Action){
  'Start' {Start-Service -InputObject $service -ErrorAction Stop}
  'Stop' {Stop-Service -InputObject $service -ErrorAction Stop}
  'Restart' {Restart-Service -InputObject $service -ErrorAction Stop}
 }
 $effects.unknown=@();$effects.completed=$requested;$operationStatus='partial'
 $desired=if($Action -eq 'Stop'){'Stopped'}else{'Running'}
 $verification.status='unknown'
 $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]$desired,[TimeSpan]::FromSeconds(30))
 $service.Refresh()
 $now=[DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
 Add-Fact actualState ([string]$service.Status) 'native SCM state after action; application API health not probed'
 if([string]$service.Status -cne $desired){$verification.status='failed';throw 'VERIFICATION_FAILED'}
 $verification=@{status='passed';checks=@(@{id='native-scm-state';status='passed';source='SCM WaitForStatus and Refresh'})}
 $operationStatus='succeeded'
} catch {
 $known=@('TARGET_MISMATCH','AUTHORIZATION_REQUIRED','PRECONDITION_CHANGED','VERIFICATION_FAILED')
 $code=[string]$_.Exception.Message
 if($code -notin $known){$code=if($effects.unknown.Count){'NATIVE_STEP_FAILED'}elseif($effects.completed.Count){'VERIFICATION_UNAVAILABLE'}else{'PRECONDITION_UNAVAILABLE'}}
 # Arbitrary native messages are not promoted into instructions or exposed with credentials.
 [void]$errors.Add(@{code=$code;message='The selected native service operation did not reach its declared postcondition; effect state is retained.'})
}
if(-not (Write-Observation 'service.apply' $false $effects $verification)){exit 1}
