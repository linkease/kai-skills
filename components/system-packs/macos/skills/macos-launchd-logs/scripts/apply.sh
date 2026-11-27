#!/bin/sh
set -u
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$script_dir/common.sh"
validate_target "${1:-}" "${2:-}"
action=${3:-};before=${4:-}
case "$action" in kickstart) after=running ;; stop) after=stopped ;; *) printf '%s\n' 'action must be kickstart or stop' >&2; exit 2 ;; esac
case "$before" in running|stopped) ;; *) printf '%s\n' 'an explicitly observed previous state is required' >&2; exit 2 ;; esac
lib="$script_dir/../../kai-system-information/scripts/lib"
[ -f "$lib/receipt.sh" ] || lib="$script_dir/../../../../common/skills/kai-system-information/scripts/lib"
[ -f "$lib/receipt.sh" ] || lib="$script_dir/../../../../../system-packs/common/skills/kai-system-information/scripts/lib"
. "$lib/receipt.sh"
. "$lib/probe.sh"
kai_operation=service.apply kai_target=${ZSETUP_TASK_TARGET_ID:-local} kai_deadline=30
kai_facts= kai_evidence= kai_errors= kai_evidence_index=0 kai_status=succeeded
kai_observed=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
kai_tmp=$(mktemp -d "${TMPDIR:-/tmp}/kai-launchd-apply.XXXXXX") || exit 2
kai_started=$(date +%s)
kai_effects_requested="[{\"id\":\"service-command\",\"kind\":\"native-launchd-action\",\"target\":$(kai_json_string "$service_target:$action")}]"
kai_effects_completed='[]' kai_effects_unknown='[]' kai_effects_remaining=$kai_effects_requested
kai_verification='{"status":"not_run","checks":[]}'
kai_emitted=0
kai_finish() { kai_emitted=1; kai_emit_operation; }
kai_cleanup() {
  if [ "$kai_emitted" = 0 ]; then
    kai_error EXECUTION_INTERRUPTED 'Execution ended without a final receipt; pending effects remain unknown.'
    kai_status=unknown; kai_finish
  fi
  rm -rf -- "$kai_tmp"
}
kai_cancel() {
  kai_error CANCELLED 'Cancellation does not prove that pending effects did not occur.'
  kai_status=cancelled; kai_finish; exit "$1"
}
trap kai_cleanup 0
trap 'kai_cancel 130' INT
trap 'kai_cancel 143' TERM HUP
fail() { kai_error "$1" "$2"; kai_status=$3; kai_finish; exit 1; }
[ "${TARGET_CHANGE_APPROVED:-}" = YES ] || fail AUTHORIZATION_REQUIRED 'An existing scoped executor authorization is required; this marker does not grant host permission.' failed
launchd_observe_state || fail PRECONDITION_UNAVAILABLE 'The current native job state could not be established.' failed
[ "$kai_state" = "$before" ] || fail PRECONDITION_CHANGED 'Native job state changed after observation.' failed
kai_effects_remaining='[]' kai_effects_unknown=$kai_effects_requested
case "$action" in kickstart) kai_probe launchctl kickstart -k "$service_target" ;; stop) kai_probe launchctl kill SIGTERM "$service_target" ;; esac
[ "$kai_probe_rc" = 0 ] || fail NATIVE_STEP_FAILED 'The native action did not complete successfully; pending effects remain uncertain.' unknown
kai_effects_completed=$kai_effects_requested kai_effects_unknown='[]'
launchd_observe_state || fail VERIFICATION_UNAVAILABLE 'The post-action native state is unknown; issued commands are not application availability.' partial
kai_observed=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
kai_fact actualState "$(kai_json_string "$kai_state")" 'native launchctl state after the explicitly selected action; application API health not probed' observed
[ "$kai_state" = "$after" ] || { kai_verification='{"status":"failed","checks":[{"id":"native-state","status":"failed"}]}'; fail VERIFICATION_FAILED 'The native process state does not match the action postcondition.' partial; }
kai_verification='{"status":"passed","checks":[{"id":"native-state","status":"passed"}]}'
kai_finish
