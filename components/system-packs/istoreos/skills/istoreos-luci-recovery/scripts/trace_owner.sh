#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec sh "$here/../../istoreos-package-manager/scripts/package.sh" owner "${1:?an explicit absolute source path is required}"
