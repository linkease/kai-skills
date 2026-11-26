#!/bin/sh
# Explicit LuCI HTTP service observation; package/source reads are separate interfaces.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec sh "$here/../resources/runtime/istoreos-service-manager/scripts/inspect.sh" --target-id "${ZSETUP_TASK_TARGET_ID:-local}" --service "${1:-uhttpd}"
