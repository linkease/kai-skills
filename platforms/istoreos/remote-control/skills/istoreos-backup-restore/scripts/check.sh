#!/bin/sh
# Query installed protection interfaces. A system protection point does not cover arbitrary external data.
set -u
umask 077
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
lib="$here/../resources/runtime/kai-system-information/scripts/lib"
[ -f "$lib/receipt.sh" ] || lib="$here/../../../../common/skills/kai-system-information/scripts/lib"
. "$lib/receipt.sh"
. "$lib/probe.sh"
kai_operation=backup.inspect kai_target=${ZSETUP_TASK_TARGET_ID:-local} kai_deadline=5
kai_facts= kai_evidence= kai_errors= kai_evidence_index=0 kai_status=succeeded
kai_observed=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
kai_tmp=$(mktemp -d "${TMPDIR:-/tmp}/kai-backup-inspect.XXXXXX") || exit 2
trap 'rm -rf -- "$kai_tmp"' 0
trap 'exit 130' INT
trap 'exit 143' TERM HUP
kai_started=$(date +%s)
if [ "$#" -ne 0 ]; then kai_status=failed; kai_error INVALID_ARGUMENT 'This query takes no positional operation arguments; its target is bound by the executor.'; kai_emit_observation; exit 2; fi
for program in changeguard linkspace; do
 path=$(command -v "$program" 2>/dev/null || :)
 if [ -n "$path" ]; then kai_fact "$program" "$(kai_json_string "$path")" 'native command lookup; presence does not establish protection' observed
 else kai_fact "$program" null 'native command lookup' absent; fi
done
if command -v changeguard >/dev/null 2>&1; then
 for operation in capabilities status; do
  kai_probe changeguard "$operation" --json
  if [ "$kai_probe_rc" -eq 0 ]; then kai_fact "$operation" "{\"untrusted\":true,\"output\":$(kai_json_string "$kai_probe_output")}" "changeguard $operation --json" observed
  else kai_probe_unknown "$operation" "changeguard $operation --json" PROTECTION_QUERY_FAILED; fi
 done
fi
kai_emit_observation
