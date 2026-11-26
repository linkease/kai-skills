#!/bin/sh
# Native OS/tool facts; no empty-string stand-ins for failed native commands.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
system_scripts="$here/../resources/runtime/kai-system-information/scripts"
[ -f "$system_scripts/inspect.sh" ] || system_scripts="$here/../../../../common/skills/kai-system-information/scripts"
exec sh "$system_scripts/inspect.sh" --target-id "${ZSETUP_TASK_TARGET_ID:-local}" --sections os,tools "$@"
