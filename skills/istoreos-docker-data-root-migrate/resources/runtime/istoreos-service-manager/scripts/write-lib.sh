#!/usr/bin/env bash
# Service-operation receipts and owned journals. No task routing or authorization grant.
op_library_here=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
op_bootstrap="$op_library_here/../../kai-tool-bootstrap/scripts/jq-env.sh"
[ -f "$op_bootstrap" ] || op_bootstrap="$op_library_here/../../../../common/skills/kai-tool-bootstrap/scripts/jq-env.sh"
[ -f "$op_bootstrap" ] || op_bootstrap="$op_library_here/../../../../../system-packs/common/skills/kai-tool-bootstrap/scripts/jq-env.sh"
. "$op_bootstrap"
if ! kai_use_jq full 2>/dev/null; then
    printf '{"schemaVersion":1,"operation":"%s","operationStatus":"failed","targetId":"unbound","readOnly":false,"observedAt":"%s","facts":{},"evidence":[],"effects":{"requested":[],"completed":[],"unknown":[],"remaining":[]},"verification":{"status":"not_run","checks":[]},"errors":[{"code":"DEPENDENCY_UNAVAILABLE","message":"An existing compatible Bash and full jq are required; no dependency was installed."}],"truncated":false}\n' "$op_name" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    exit 2
fi
umask 077
op_now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
op_target=${ZSETUP_TASK_TARGET_ID:-unbound} op_status=failed op_facts='{}' op_evidence='[]' op_errors='[]'
op_requested='[]' op_completed='[]' op_unknown='[]' op_remaining='[]'
op_verification='{"status":"not_run","checks":[]}'
op_job= op_lock= op_lock_owned=0 op_emitted=0 op_request_digest= op_activation_temporary=

op_receipt() {
    jq -cn --arg operation "$op_name" --arg target "$op_target" --arg now "$op_now" --arg status "$op_status" \
      --argjson facts "$op_facts" --argjson evidence "$op_evidence" --argjson errors "$op_errors" \
      --argjson requested "$op_requested" --argjson completed "$op_completed" --argjson unknown "$op_unknown" --argjson remaining "$op_remaining" --argjson verification "$op_verification" \
      '{schemaVersion:1,operation:$operation,operationStatus:$status,targetId:$target,readOnly:false,observedAt:$now,facts:$facts,evidence:$evidence,effects:{requested:$requested,completed:$completed,unknown:$unknown,remaining:$remaining},verification:$verification,errors:$errors,truncated:false}'
}
op_journal() {
    [ -n "$op_job" ] || return 0
    local receipt stage
    receipt=$(op_receipt) || return 1
    stage=$(mktemp "$op_job/.receipt.XXXXXX") || return 1
    jq -cn --arg digest "$op_request_digest" --argjson receipt "$receipt" '{schemaVersion:1,requestSHA256:$digest,receipt:$receipt}' >"$stage" && mv -- "$stage" "$op_job/receipt.json"
}
op_fact() {
    op_facts=$(jq -c --arg name "$1" --argjson value "$2" '.+{($name):$value}' <<< "$op_facts")
    op_evidence=$(jq -c --arg name "$1" --arg source "$3" --arg now "$op_now" '.+[{id:("fact-"+$name),source:$source,status:"observed",observedAt:$now,factPaths:[("/facts/"+$name)]}]' <<< "$op_evidence")
}
op_error() { op_errors=$(jq -c --arg code "$1" --arg message "$2" '.+[{code:$code,message:$message}]' <<< "$op_errors"); }
op_emit() {
    local receipt
    receipt=$(op_receipt) || exit 2
    # The result is bounded; diagnostics remain in this operation's private journal.
    if [ "$(printf '%s' "$receipt" | wc -c)" -gt 8192 ]; then
        op_errors='[{"code":"RESULT_LIMIT","message":"Operation receipt exceeded its byte budget; effects remain in the private journal."}]'
        op_facts='{}' op_evidence='[]' op_status=unknown
        receipt=$(op_receipt)
    fi
    op_journal || { op_error JOURNAL_WRITE_FAILED 'The current receipt could not be persisted.'; op_status=unknown; receipt=$(op_receipt); }
    printf '%s\n' "$receipt"
    op_emitted=1
}
op_fail() {
    op_error "$1" "$2"
    case "$1" in VERIFICATION_UNAVAILABLE) op_verification=$(jq -c '.status="unknown"' <<< "$op_verification") ;; esac
    if [ "$(jq length <<< "$op_unknown")" -gt 0 ]; then op_status=unknown
    elif [ "$(jq length <<< "$op_completed")" -gt 0 ]; then op_status=partial
    else op_status=failed; fi
    op_emit
    exit "${3:-1}"
}
op_cleanup() {
    local code=$?
    if [ "$op_emitted" = 0 ]; then
        op_error EXECUTION_INTERRUPTED 'Execution ended without a final receipt; pending effects remain unknown.'
        op_status=unknown
        op_emit
    fi
    if [ "$op_lock_owned" = 1 ]; then rmdir -- "$op_lock" 2>/dev/null || :; fi
    [ -z "$op_activation_temporary" ] || rm -f -- "$op_activation_temporary"
    return "$code"
}
op_cancel() { op_status=cancelled; op_error CANCELLED 'Cancellation does not prove that pending effects did not occur.'; op_emit; exit "$1"; }
trap op_cleanup EXIT
trap 'op_cancel 130' INT
trap 'op_cancel 143' TERM HUP
op_hash() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d ' ' -f1; else shasum -a 256 "$1" | cut -d ' ' -f1; fi; }
op_expected_hash() {
    local actual=absent
    if [ -e "$1" ] || [ -L "$1" ]; then
        [ -f "$1" ] && [ ! -L "$1" ] || op_fail PRECONDITION_CHANGED 'A declared source/configuration is not a regular file.'
        actual=$(op_hash "$1") || op_fail PRECONDITION_UNAVAILABLE 'A declared source/configuration digest could not be read.'
    fi
    [ "$actual" = "$2" ] || op_fail PRECONDITION_CHANGED 'A declared source/configuration changed after observation.'
}
op_init() {
    local request=$1 state id prior state_mode
    [ -f "$request" ] && [ ! -L "$request" ] && [ "$(wc -c < "$request")" -le 8192 ] || op_fail INVALID_ARGUMENT 'Request must be a bounded regular JSON file.' 2
    op_request=$(cat -- "$request")
    # jq's normal parser overwrites duplicate keys. Inspect key tokens before
    # normalization, target selection, hashing or creation of operation state.
    command -v awk >/dev/null 2>&1 && [ -f "$op_library_here/unique-keys.awk" ] || op_fail DEPENDENCY_UNAVAILABLE 'The existing request-key validator is unavailable; no operation was started.' 2
    printf '%s' "$op_request" | LC_ALL=C awk -f "$op_library_here/unique-keys.awk" | jq -se 'any(.[]; .==[-1,"complete"]) and (group_by(.[0]) | all(.[]; length == (map(.[1]) | unique | length)))' >/dev/null || op_fail INVALID_ARGUMENT 'Request JSON must be valid and contain no duplicate object keys.' 2
    jq -e --arg operation "$op_name" 'type=="object" and (keys==["operation","parameters","schemaVersion","targetId"]) and .schemaVersion==1 and .operation==$operation and (.parameters|type=="object") and (.targetId|type=="string" and length>0 and length<=200)' <<< "$op_request" >/dev/null || op_fail INVALID_ARGUMENT 'An explicit versioned operation request is required.' 2
    op_target=$(jq -r .targetId <<< "$op_request")
    [ "$op_target" = "${ZSETUP_TASK_TARGET_ID:-local}" ] || op_fail TARGET_MISMATCH 'The request does not match the executor target.' 2
    id=$(jq -r '.parameters.operationId//""' <<< "$op_request")
    [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$ ]] || op_fail INVALID_ARGUMENT 'An explicit operationId is required.' 2
    state=${KAI_OPERATION_STATE_DIR:-}
    [ -n "$state" ] && [ -d "$state" ] && [ ! -L "$state" ] && [ -O "$state" ] || op_fail CONTEXT_UNAVAILABLE 'An existing executor-owned state directory is required.' 2
    [ "$(CDPATH= cd -- "$state" && pwd -P)" = "$state" ] || op_fail CONTEXT_UNAVAILABLE 'State directory must be an explicit physical absolute path.' 2
    state_mode=$(stat -c '%a' "$state") || op_fail CONTEXT_UNAVAILABLE 'State directory permissions could not be verified.' 2
    [[ "$state_mode" =~ ^[0-7]{3,4}$ ]] && [ "$((8#$state_mode & 0022))" = 0 ] || op_fail CONTEXT_UNAVAILABLE 'Operation state must not be writable by another identity.' 2
    op_job="$state/$id";op_lock="$state/$id.lock"
    if ! mkdir -- "$op_lock" 2>/dev/null; then op_job=;op_fail OPERATION_BUSY 'This operation has an active or interrupted lock; it was not replayed.' 2; fi
    op_lock_owned=1
    op_request_digest=$(printf '%s' "$op_request" | jq -Sc . | { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; } | cut -d ' ' -f1)
    if [ -e "$op_job" ] || [ -L "$op_job" ]; then
        [ -d "$op_job" ] && [ ! -L "$op_job" ] && [ -O "$op_job" ] && [ -f "$op_job/receipt.json" ] && [ ! -L "$op_job/receipt.json" ] && [ -O "$op_job/receipt.json" ] || { op_job=;op_fail OPERATION_CONFLICT 'Operation state is not an owned journal.' 2; }
        prior=$(cat -- "$op_job/receipt.json")
        if ! jq -e --arg digest "$op_request_digest" '.requestSHA256==$digest' <<< "$prior" >/dev/null; then op_job=;op_fail OPERATION_CONFLICT 'An operation ID cannot be reused with different parameters.' 2; fi
        # Same ID returns historical evidence, never a second installation/restart/copy.
        jq -c .receipt <<< "$prior"
        op_emitted=1
        [ "$(jq -r .receipt.operationStatus <<< "$prior")" = succeeded ] && exit 0
        exit 1
    fi
    mkdir -- "$op_job" || { op_job=;op_fail CONTEXT_UNAVAILABLE 'Cannot create the private operation journal.' 2; }
    op_fact operationId "$(jq -cn --arg id "$id" '$id')" 'explicit operation identity; repeated IDs return historical receipts without replay'
    op_status=unknown
    op_error IN_PROGRESS 'Operation has not reached a final state.'
    op_journal || op_fail JOURNAL_WRITE_FAILED 'Cannot persist initial operation context.'
    op_errors='[]' op_status=failed
}
op_effect() {
    local effect
    effect=$(jq -cn --arg id "$1" --arg kind "$2" --arg target "$3" '{id:$id,kind:$kind,target:$target}')
    op_requested=$(jq -c --argjson effect "$effect" '.+[$effect]' <<< "$op_requested")
    op_remaining=$(jq -c --argjson effect "$effect" '.+[$effect]' <<< "$op_remaining")
}
op_executor() {
    op_timeout=$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || :)
    [ -n "$op_timeout" ] || op_fail BOUNDED_EXECUTOR_UNAVAILABLE 'An existing timeout executor is required; nothing was installed.' 2
    op_seconds=$(jq -r '.parameters.timeoutSeconds//60' <<< "$op_request")
    [[ "$op_seconds" =~ ^[1-9][0-9]{0,2}$ ]] && [ "$op_seconds" -le 300 ] || op_fail INVALID_ARGUMENT 'Operation timeout must be 1..300 seconds.' 2
}
op_native() {
    op_native_code=0
    (ulimit -f 64; exec "$op_timeout" -k 2 "$op_seconds" "$@") >"$op_job/native.stdout" 2>"$op_job/native.stderr" || op_native_code=$?
    if [ "$(wc -c < "$op_job/native.stdout")" -gt 16384 ] || [ "$(wc -c < "$op_job/native.stderr")" -gt 16384 ]; then op_native_code=126; fi
    return "$op_native_code"
}
op_run_effect() {
    local id=$1 effect
    shift
    effect=$(jq -c --arg id "$id" '.[]|select(.id==$id)' <<< "$op_requested")
    [ -n "$effect" ] || op_fail EFFECT_SCOPE_MISMATCH 'The step is outside the declared operation scope.'
    op_remaining=$(jq -c --arg id "$id" 'map(select(.id!=$id))' <<< "$op_remaining")
    op_unknown=$(jq -c --argjson effect "$effect" '.+[$effect]' <<< "$op_unknown")
    op_status=unknown;op_error IN_PROGRESS 'A declared native step is pending; its side effects are not yet known.'
    op_journal || op_fail JOURNAL_WRITE_FAILED 'Cannot persist pending effect; native step was not started.'
    op_errors='[]'
    if ! op_native "$@"; then op_fail NATIVE_STEP_FAILED "The native step returned code $op_native_code; its effects remain uncertain and its private diagnostics are retained."; fi
    op_unknown=$(jq -c --arg id "$id" 'map(select(.id!=$id))' <<< "$op_unknown")
    op_completed=$(jq -c --argjson effect "$effect" '.+[$effect]' <<< "$op_completed")
    op_error IN_PROGRESS 'Postconditions have not yet been verified.'
    op_journal || op_fail JOURNAL_WRITE_FAILED 'The completed step could not be journaled.'
    op_errors='[]'
}
op_check() {
    local id=$1 passed=$2 source=$3
    op_verification=$(jq -c --arg id "$id" --argjson passed "$passed" --arg source "$source" --arg now "$op_now" '.checks+=[{id:$id,status:(if $passed then "passed" else "failed" end),passed:$passed,source:$source,observedAt:$now}]|.status=(if all(.checks[];.status=="passed") then "passed" else "failed" end)' <<< "$op_verification")
    [ "$passed" = true ] || op_fail VERIFICATION_FAILED 'A declared postcondition did not pass; issued commands are not application health.'
}
op_success() {
    [ "$(jq length <<< "$op_unknown")" = 0 ] && [ "$(jq length <<< "$op_remaining")" = 0 ] && [ "$(jq -r .status <<< "$op_verification")" = passed ] || op_fail VERIFICATION_INCOMPLETE 'Declared effects and postconditions are incomplete.'
    op_status=succeeded
    op_emit
}
