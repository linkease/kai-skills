#!/bin/sh
set -eu
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
. "$script_dir/common.sh"
validate_target "${1:-}" "${2:-}"
action="${3:-}"
case "$action" in kickstart|stop) ;; *) echo "failed: action must be kickstart or stop" >&2; exit 2 ;; esac

printf 'target=%s\naction=%s\napproval_required=true\nverify=%s\n' "$service_target" "$action" "launchctl print $service_target"
