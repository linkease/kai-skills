#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
system_scripts="$here/../../kai-system-information/scripts"
[ -f "$system_scripts/inspect.sh" ] || system_scripts="$here/../../../../common/skills/kai-system-information/scripts"
exec sh "$system_scripts/observe.sh" --target-id "${ZSETUP_TASK_TARGET_ID:-local}" --source "${1:-filesystems}"
