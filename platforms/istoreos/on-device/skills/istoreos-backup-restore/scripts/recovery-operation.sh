#!/usr/bin/env bash
# One explicit native checkpoint operation. ChangeGuard owns validated storage,
# immutable preview checks, restoration workers in /tmp and durable job state.
set -euo pipefail
op_here=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
. "$op_here/../resources/runtime/istoreos-service-manager/scripts/write-lib.sh"
[ "$#" = 1 ] || op_fail INVALID_ARGUMENT 'A versioned checkpoint operation request is required; archive paths are not checkpoint identities.' 2
op_init "$1"
[ "${KAIPLUS_CONFIRMED:-}" = 1 ] || op_fail AUTHORIZATION_REQUIRED 'An existing scoped executor authorization marker is required; no permission is granted by this script.' 2
op_executor
recovery_program=${KAI_CHANGEGUARD_BIN:-$(command -v changeguard 2>/dev/null || :)}
[ -n "$recovery_program" ] && [ -x "$recovery_program" ] || op_fail DEPENDENCY_UNAVAILABLE 'The native ChangeGuard interface is unavailable; no backup backend was selected or installed.' 2
recovery_config=()
if [ -n "${KAI_CHANGEGUARD_CONFIG:-}" ]; then recovery_config=(--config "$KAI_CHANGEGUARD_CONFIG"); fi
recovery_call() { local command=$1;shift;op_native "$recovery_program" "$command" "${recovery_config[@]}" "$@" --json; }
recovery_call capabilities || op_fail DEPENDENCY_UNAVAILABLE 'Native recovery capabilities could not be read.' 2
jq -e '.schemaVersion==1 and .status=="succeeded" and .result.module=="changeguard" and .result.protocolVersion==1' "$op_job/native.stdout" >/dev/null || op_fail UNSUPPORTED_BACKEND 'The installed native recovery protocol is unsupported.' 2
recovery_id=$(jq -r .parameters.operationId <<< "$op_request")
case "$op_name" in
 recovery.backup)
  jq -e '.parameters|((keys-["operationId","templateId","timeoutSeconds"])|length==0) and (.templateId|type=="string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$") and (contains("..")|not))' <<< "$op_request" >/dev/null || op_fail INVALID_ARGUMENT 'An explicit registered template ID is required; no scope or repository is chosen.' 2
  jq -e '.result.implemented|index("backup")!=null' "$op_job/native.stdout" >/dev/null || op_fail UNSUPPORTED_BACKEND 'The selected checkpoint interface is unavailable.' 2
  recovery_template=$(jq -r .parameters.templateId <<< "$op_request")
  op_effect checkpoint-create native-checkpoint-create "$recovery_template"
  op_run_effect checkpoint-create "$recovery_program" backup "${recovery_config[@]}" --template "$recovery_template" --request-id "$recovery_id" --owner "${KAI_OPERATION_OWNER:-}" --json
  jq -e --arg template "$recovery_template" --arg request "$recovery_id" '.schemaVersion==1 and .status=="succeeded" and .result.requestID==$request and .result.template.id==$template and .result.state=="complete" and (.result.id|type=="string" and length>0)' "$op_job/native.stdout" >/dev/null || op_fail VERIFICATION_FAILED 'The provider did not return a completed checkpoint for this exact request and template.'
  recovery_summary=$(jq -c '.result|{id,requestID,state,deviceID,templateId:.template.id,templateSHA256,createdAt,rootCount:(.roots|length),warnings,error,untrusted:true}' "$op_job/native.stdout")
  op_fact checkpoint "$recovery_summary" 'native ChangeGuard completed checkpoint record; scope is the explicitly selected frozen template'
  op_check checkpoint-complete true 'native provider completed the requested checkpoint; directory presence alone is not a backup'
  op_success
  ;;
 recovery.restore)
  jq -e '.parameters|((keys-["operationId","checkpointId","diffId","verificationScope","timeoutSeconds"])|length==0) and ([.checkpointId,.diffId]|all(type=="string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$") and (contains("..")|not))) and (.verificationScope as $s|["files","files-and-services"]|index($s)!=null)' <<< "$op_request" >/dev/null || op_fail INVALID_ARGUMENT 'An explicit checkpoint, immutable preview diff and verification scope are required; no rollback direction is inferred.' 2
  jq -e '.result.implemented|(index("restore-start")!=null and index("restore-job")!=null)' "$op_job/native.stdout" >/dev/null || op_fail UNSUPPORTED_BACKEND 'The installed backend does not provide durable checked restore jobs.' 2
  recovery_checkpoint=$(jq -r .parameters.checkpointId <<< "$op_request")
  recovery_diff=$(jq -r .parameters.diffId <<< "$op_request")
  recovery_verification=$(jq -r .parameters.verificationScope <<< "$op_request")
  op_fact recoveryIdentity "$(jq -cn --arg id "$recovery_id" --arg checkpoint "$recovery_checkpoint" --arg diff "$recovery_diff" --arg scope "$recovery_verification" '{operationId:$id,checkpointId:$checkpoint,diffId:$diff,verificationScope:$scope}')" 'explicit restore identity; the provider rechecks preview, device and bound storage before changing files'
  op_effect native-restore native-checked-restore "$recovery_checkpoint"
  op_remaining='[]';op_unknown=$op_requested;op_status=unknown
  op_error IN_PROGRESS 'A durable native restore is pending; no restore completion has been observed.'
  op_journal || op_fail JOURNAL_WRITE_FAILED 'Cannot persist the native restore identity; nothing was dispatched.'
  op_errors='[]'
  recovery_call restore-start --id "$recovery_checkpoint" --other "$recovery_diff" --request-id "$recovery_id" || op_fail NATIVE_RESTORE_REQUEST_FAILED 'The native restore request did not complete successfully; consult its persisted job identity before retrying.'
  jq -e --arg id "$recovery_id" '.schemaVersion==1 and .status=="succeeded" and .result.id==$id' "$op_job/native.stdout" >/dev/null || op_fail PROVIDER_RESULT_INVALID 'The native acknowledgement does not match this restore request.'
  recovery_call restore-job --id "$recovery_id" || op_fail VERIFICATION_UNAVAILABLE 'The native job state could not be read; request acceptance is not restore completion.'
  jq -e --arg id "$recovery_id" --arg checkpoint "$recovery_checkpoint" --arg diff "$recovery_diff" '.schemaVersion==1 and .status=="succeeded" and .result.id==$id and .result.checkpointID==$checkpoint and .result.diffID==$diff' "$op_job/native.stdout" >/dev/null || op_fail PROVIDER_RESULT_INVALID 'The native job record does not match the exact request, checkpoint and preview.'
  recovery_summary=$(jq -c '.result|{id,checkpointID,diffID,state,error,run:(.run|if type=="object" then {id,checkpointID,state,phase,filesRestored,servicesRestored,externalReachability,rebootRequired,consistency,appliedCount,driftedCount,failedCount,error} else null end),untrusted:true}' "$op_job/native.stdout")
  op_fact providerJob "$recovery_summary" 'native durable restore-job record; files, runtime services and external reachability remain distinct'
  recovery_state=$(jq -r '.result.state//"unknown"' "$op_job/native.stdout")
  [ "$recovery_state" = completed ] || op_fail RECOVERY_NOT_COMPLETE 'The provider has not completed this restore; retained state is queryable and no request was replayed.'
  jq -e --arg checkpoint "$recovery_checkpoint" --arg scope "$recovery_verification" '.result.run|.checkpointID==$checkpoint and .state=="completed" and .filesRestored==true and (if $scope=="files-and-services" then .servicesRestored==true else true end)' "$op_job/native.stdout" >/dev/null || op_fail VERIFICATION_FAILED 'The actual native phase results do not meet the explicitly requested verification scope.'
  op_unknown='[]';op_completed=$op_requested
  op_check requested-restore-scope true 'native terminal run and actual files/services phase results; external client reconnection is not inferred'
  op_success
  ;;
 *) op_fail INVALID_ARGUMENT 'Unsupported explicit recovery operation.' 2 ;;
esac
