#!/bin/sh
# Compatibility entry: service observation only. Engine API is a separate system.inspect scope.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec sh "$here/../resources/runtime/istoreos-service-manager/scripts/inspect.sh" --target-id "${ZSETUP_TASK_TARGET_ID:-local}" --service dockerd "$@"
