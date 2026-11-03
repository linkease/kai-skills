#!/bin/sh
set -eu
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
. "$script_dir/common.sh"
validate_target "${1:-}" "${2:-}"
expected="${3:-running}"
case "$expected" in running|stopped) ;; *) echo "failed: expected must be running or stopped" >&2; exit 2 ;; esac

if launchctl print "$service_target" >/dev/null 2>&1; then
  state=running
else
  state=stopped
fi
printf 'target=%s\nstate=%s\nexpected=%s\n' "$service_target" "$state" "$expected"
[ "$state" = "$expected" ]
