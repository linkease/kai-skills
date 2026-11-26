#!/bin/sh
# Compatibility for explicit startup-source inspection. No script is executed.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec sh "$here/../resources/runtime/istoreos-service-manager/scripts/inspect.sh" --target-id "${ZSETUP_TASK_TARGET_ID:-local}" --service "${1:?a service identifier is required}" --sections init,config,ownership
