#!/bin/sh
set -eu
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
. "$script_dir/common.sh"
validate_target "${1:-}" "${2:-}"
action="${3:-}"
[ "${TARGET_CHANGE_APPROVED:-}" = YES ] || { echo "failed: scoped approval is required" >&2; exit 3; }

case "$action" in
  kickstart) launchctl kickstart -k "$service_target" ;;
  stop) launchctl kill SIGTERM "$service_target" ;;
  *) echo "failed: action must be kickstart or stop" >&2; exit 2 ;;
esac
