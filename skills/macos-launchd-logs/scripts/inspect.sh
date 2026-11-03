#!/bin/sh
set -eu
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
. "$script_dir/common.sh"
validate_target "${1:-}" "${2:-}"

printf '%s\n' "target=$service_target"
launchctl print "$service_target" 2>&1 | head -c 6144 || true
printf '\nrecent_logs:\n'
log show --style compact --last 15m --predicate "eventMessage CONTAINS '$label'" 2>&1 | tail -n 20 | head -c 2048 || true
