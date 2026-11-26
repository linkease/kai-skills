#!/bin/sh
# Compatibility alias for one explicit service request, never infer services from a package.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec bash "$here/../../istoreos-service-manager/scripts/apply.sh" "$@"
