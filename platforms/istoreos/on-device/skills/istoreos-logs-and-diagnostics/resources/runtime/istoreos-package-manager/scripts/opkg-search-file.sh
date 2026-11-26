#!/bin/sh
set -eu
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
exec sh "$here/legacy-query.sh" owner "${1:?a file path or pattern is required}" "${2:-30}"
