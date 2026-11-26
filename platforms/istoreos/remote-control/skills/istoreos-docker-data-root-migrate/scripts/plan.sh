#!/bin/sh
# Current configuration evidence; no automatic migration source or destination choice.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec sh "$here/../resources/runtime/istoreos-service-manager/scripts/inspect.sh" --target-id "${ZSETUP_TASK_TARGET_ID:-local}" --service dockerd --sections config,runtime
