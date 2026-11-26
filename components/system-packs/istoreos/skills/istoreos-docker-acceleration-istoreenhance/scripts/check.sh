#!/bin/sh
# Existing acceleration service evidence only; no DNS test, download, install or restart.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec sh "$here/../../istoreos-service-manager/scripts/inspect.sh" --target-id "${ZSETUP_TASK_TARGET_ID:-local}" --service istoreenhance
