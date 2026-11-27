#!/bin/sh
# Compatibility entry: all observed filesystems, without choosing an install location.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
system_scripts="$here/../../kai-system-information/scripts"
[ -f "$system_scripts/observe.sh" ] || system_scripts="$here/../../../../common/skills/kai-system-information/scripts"
[ -f "$system_scripts/observe.sh" ] || system_scripts="$here/../../../../../system-packs/common/skills/kai-system-information/scripts"
exec sh "$system_scripts/observe.sh" --target-id "${ZSETUP_TASK_TARGET_ID:-local}" --source filesystems
