#!/bin/sh
# Explicit launchd observation; does not load, unload, kickstart, or execute job files.
set -u
umask 077
kai_here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$kai_here/common.sh"
validate_target "${1:-}" "${2:-}"
shift 2
kai_lib="$kai_here/../../kai-system-information/scripts/lib"
[ -f "$kai_lib/receipt.sh" ] || kai_lib="$kai_here/../../../../common/skills/kai-system-information/scripts/lib"
. "$kai_lib/receipt.sh"
. "$kai_lib/probe.sh"
kai_operation=service.inspect kai_target=${ZSETUP_TASK_TARGET_ID:-local} kai_source=${1:-startup}
kai_deadline=5 kai_facts= kai_evidence= kai_errors= kai_evidence_index=0 kai_status=succeeded
kai_observed=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
kai_tmp=$(mktemp -d "${TMPDIR:-/tmp}/kai-launchd-inspect.XXXXXX") || exit 2
trap 'rm -rf -- "$kai_tmp"' 0
trap 'exit 130' INT
trap 'exit 143' TERM HUP
kai_started=$(date +%s)
case "$kai_source" in
  startup) set -- launchctl print "$service_target" ;;
  logs) set -- log show --style compact --last 15m --predicate "eventMessage CONTAINS '$label'" ;;
  *) kai_status=failed; kai_error INVALID_ARGUMENT 'Source must be startup or logs.'; kai_emit_observation; exit 2 ;;
esac
kai_fact service "$(kai_json_string "$service_target")" 'explicit launchd domain/label; not an API health verdict' observed
kai_probe "$@"
if [ "$kai_probe_rc" -eq 0 ]; then
  kai_text=$(printf '%s' "$kai_probe_output" | sed -E -e 's#(://)[^/@[:space:]]+:[^/@[:space:]]+@#\1[REDACTED]@#g' -e 's#((password|token|secret|authorization|api_key)[[:space:]]*[:=][[:space:]]*).*#\1[REDACTED]#gI')
  kai_fact observation "{\"scope\":$(kai_json_string "$kai_source"),\"untrusted\":true,\"output\":$(kai_json_string "$kai_text")}" "$*" observed
else kai_probe_unknown observation "$*" LAUNCHD_QUERY_FAILED; fi
kai_emit_observation
