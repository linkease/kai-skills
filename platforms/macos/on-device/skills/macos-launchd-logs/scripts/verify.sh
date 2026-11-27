#!/bin/sh
set -u
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$script_dir/common.sh"
validate_target "${1:-}" "${2:-}"
expected=${3:-}
case "$expected" in running|stopped) ;; *) printf '%s\n' 'an explicit expected state (running or stopped) is required' >&2; exit 2 ;; esac
lib="$script_dir/../resources/runtime/kai-system-information/scripts/lib"
[ -f "$lib/receipt.sh" ] || lib="$script_dir/../../../../common/skills/kai-system-information/scripts/lib"
[ -f "$lib/receipt.sh" ] || lib="$script_dir/../../../../../system-packs/common/skills/kai-system-information/scripts/lib"
. "$lib/receipt.sh"
. "$lib/probe.sh"
kai_operation=service.verify kai_target=${ZSETUP_TASK_TARGET_ID:-local} kai_deadline=5
kai_facts= kai_evidence= kai_errors= kai_evidence_index=0 kai_status=succeeded
kai_observed=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
kai_tmp=$(mktemp -d "${TMPDIR:-/tmp}/kai-launchd-verify.XXXXXX") || exit 2
trap 'rm -rf -- "$kai_tmp"' 0
trap 'exit 130' INT
trap 'exit 143' TERM HUP
kai_started=$(date +%s)
kai_fact expectedState "$(kai_json_string "$expected")" 'explicit comparison parameter, not an application health requirement' observed
if launchd_observe_state; then
 kai_fact actualState "$(kai_json_string "$kai_state")" 'native launchctl state field; registered is not running and process state is not API health' observed
 if [ "$kai_state" != "$expected" ]; then kai_status=failed; kai_error STATE_MISMATCH 'Observed native process state differs from the requested comparison.'; fi
else kai_probe_unknown actualState 'native launchctl state field' STATE_UNAVAILABLE; fi
kai_emit_observation
