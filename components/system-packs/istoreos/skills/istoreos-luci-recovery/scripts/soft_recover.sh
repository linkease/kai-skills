#!/bin/sh
# Compatibility name: performs only the explicitly requested service.apply operation.
# No package install, directory selection, guessed UCI enable flag, cache deletion or fallback action.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec bash "$here/../../istoreos-service-manager/scripts/apply.sh" "$@"
