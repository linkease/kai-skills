#!/bin/sh
# Scope names are explicit observations, not automatic repairs or systools execution.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
system_scripts="$here/../../kai-system-information/scripts"
[ -f "$system_scripts/inspect.sh" ] || system_scripts="$here/../../../../common/skills/kai-system-information/scripts"
[ -f "$system_scripts/inspect.sh" ] || system_scripts="$here/../../../../../system-packs/common/skills/kai-system-information/scripts"
target=${ZSETUP_TASK_TARGET_ID:-local}
case "${1:-all}" in
  all|upgrade) exec sh "$system_scripts/inspect.sh" --target-id "$target" --sections os,tools ;;
  network) exec sh "$system_scripts/observe.sh" --target-id "$target" --source "${2:-addresses}" ;;
  storage) exec sh "$system_scripts/observe.sh" --target-id "$target" --source filesystems ;;
  store) exec sh "$here/../../istoreos-package-manager/scripts/package.sh" installed luci-app-store ;;
  *) printf '%s\n' 'unsupported observation scope' >&2; exit 2 ;;
esac
