#!/usr/bin/env bash
# Execute a locally reviewed immutable artifact; never fetch or select an installer backend.
set -euo pipefail
op_name=artifact.execute
op_here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$op_here/../resources/runtime/istoreos-service-manager/scripts/write-lib.sh"
[ "$#" = 1 ] || op_fail INVALID_ARGUMENT 'Usage: run.sh REQUEST_JSON; source hash, runner, arguments and working directory must be explicit.' 2
op_init "$1"
jq -e '.parameters|((keys-["operationId","path","sha256","runner","arguments","workingDirectory","timeoutSeconds"])|length==0) and
 (.path|type=="string" and startswith("/") and length<=512 and (test("[[:cntrl:]]")|not)) and
 (.sha256|type=="string" and test("^[a-f0-9]{64}$")) and
 (.workingDirectory|type=="string" and startswith("/") and length<=512 and (test("[[:cntrl:]]")|not)) and
 (.runner as $r|["native","sh","bash","dotrun"]|index($r)!=null) and
 (.arguments|type=="array" and length<=100 and all(.[];type=="string" and length<=512 and (contains("\u0000")|not)))' <<< "$op_request" >/dev/null || op_fail INVALID_ARGUMENT 'Only an explicit local artifact execution request is supported; URLs are not executable inputs.' 2
[ "${KAIPLUS_CONFIRMED:-}" = 1 ] || [ "${CONFIRM_RUN_EXEC:-}" = YES ] || op_fail AUTHORIZATION_REQUIRED 'An existing scoped execution authorization marker is required; it does not grant host permissions.' 2
op_executor
artifact_path=$(jq -r .parameters.path <<< "$op_request")
artifact_sha=$(jq -r .parameters.sha256 <<< "$op_request")
artifact_runner=$(jq -r .parameters.runner <<< "$op_request")
artifact_directory=$(jq -r .parameters.workingDirectory <<< "$op_request")
[ -d "$artifact_directory" ] && [ ! -L "$artifact_directory" ] && [ "$(CDPATH= cd -- "$artifact_directory" && pwd -P)" = "$artifact_directory" ] || op_fail INVALID_ARGUMENT 'Working directory must be an existing physical directory.' 2
op_expected_hash "$artifact_path" "$artifact_sha"
mkdir -- "$op_job/artifact"
artifact_staged="$op_job/artifact/$(basename -- "$artifact_path")"
cp -p -- "$artifact_path" "$artifact_staged" || op_fail PRECONDITION_UNAVAILABLE 'Cannot stage an owned copy of the selected self-contained artifact.'
op_expected_hash "$artifact_staged" "$artifact_sha"
artifact_args=()
while IFS= read -r -d '' argument; do artifact_args+=("$argument"); done < <(jq -j '.parameters.arguments[]|.,"\u0000"' <<< "$op_request")
case "$artifact_runner" in
 native) [ -x "$artifact_staged" ] || op_fail PRECONDITION_UNAVAILABLE 'Native execution requires an existing executable mode; the source was not chmodded.'; artifact_command=("$artifact_staged") ;;
 sh|bash) command -v "$artifact_runner" >/dev/null 2>&1 || op_fail DEPENDENCY_UNAVAILABLE 'The selected interpreter is unavailable.' 2; artifact_command=(env -u BASH_ENV -u ENV "$artifact_runner" -- "$artifact_staged") ;;
 dotrun)
  command -v is-opkg >/dev/null 2>&1 || op_fail DEPENDENCY_UNAVAILABLE 'The explicitly selected dotrun integration is unavailable; no other runner was selected.' 2
  [ "${#artifact_args[@]}" = 0 ] || op_fail INVALID_ARGUMENT 'This native dotrun interface does not support artifact arguments.' 2
  artifact_command=(is-opkg dotrun "$artifact_staged") ;;
esac
op_fact artifact "$(jq -cn --arg path "$artifact_path" --arg executed "$artifact_staged" --arg sha "$artifact_sha" --arg runner "$artifact_runner" '{path:$path,executedCopy:$executed,sha256:$sha,runner:$runner,applicationHealth:"not-inferred",filesystemEffects:"not-inferred-from-exit-code"}')" 'explicit artifact identity and verified owned copy; no download or package backend selection'
op_effect artifact-execution execute-reviewed-artifact "$artifact_path"
cd -- "$artifact_directory"
op_expected_hash "$artifact_staged" "$artifact_sha"
op_run_effect artifact-execution "${artifact_command[@]}" "${artifact_args[@]}"
op_check native-exit-code true 'selected artifact process exited zero; this is not application health or user-task completion'
op_success
