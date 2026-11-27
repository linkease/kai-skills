#!/bin/sh
# Named, read-only native observations. No free-form shell commands or business intent.
set -u
umask 077
kai_here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$kai_here/lib/receipt.sh"
. "$kai_here/lib/probe.sh"
kai_operation=system.observe kai_target= kai_source= kai_deadline=5
kai_facts= kai_evidence= kai_errors= kai_evidence_index=0 kai_status=succeeded kai_tmp=
kai_observed=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
trap '[ -z "$kai_tmp" ] || rm -rf -- "$kai_tmp"' 0
trap 'exit 130' INT
trap 'exit 143' TERM HUP
kai_invalid() { kai_target=${kai_target:-unbound}; kai_status=failed; kai_error INVALID_ARGUMENT "$1"; kai_emit_observation; exit 2; }
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || kai_invalid 'Missing option value.'
  case "$1" in --target-id) kai_target=$2 ;; --source) kai_source=$2 ;; --deadline-seconds) kai_deadline=$2 ;; *) kai_invalid 'Unknown option.' ;; esac
  shift 2
done
[ -n "$kai_target" ] && [ "${#kai_target}" -le 200 ] || kai_invalid 'A bound target ID is required.'
kai_require_bound_target || exit 2
case "$kai_deadline" in ''|*[!0-9]*) kai_invalid 'Invalid deadline.' ;; esac
[ "${#kai_deadline}" -le 2 ] && [ "$kai_deadline" -ge 1 ] && [ "$kai_deadline" -le 30 ] || kai_invalid 'Deadline must be 1..30 seconds.'
case "$kai_source" in
  filesystems) set -- df -Pk ;;
  inodes) set -- df -Pi ;;
  mounts) set -- mount ;;
  addresses) set -- ip -j address show ;;
  routes) set -- ip -j route show table all ;;
  listeners) set -- ss -lntu ;;
  *) kai_invalid 'Sources: filesystems, inodes, mounts, addresses, routes, listeners. Availability is platform dependent.' ;;
esac
kai_tmp=$(mktemp -d "${TMPDIR:-/tmp}/kai-system-observe.XXXXXX") || exit 2
kai_started=$(date +%s)
if ! command -v "$1" >/dev/null 2>&1; then
  kai_fact observation null "$kai_source" unsupported
  kai_error SOURCE_UNAVAILABLE 'The native command is unavailable; nothing was installed.'
else
  kai_probe "$@"
  if [ "$kai_probe_rc" -eq 0 ]; then
    kai_fact observation "{\"source\":$(kai_json_string "$kai_source"),\"untrusted\":true,\"output\":$(kai_json_string "$kai_probe_output")}" "$*" observed
  else kai_probe_unknown observation "$*" NATIVE_QUERY_FAILED; fi
fi
kai_emit_observation
