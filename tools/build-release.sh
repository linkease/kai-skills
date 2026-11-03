#!/bin/sh
set -eu
root="${LINKEASE_SKILLS_ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)}"
if [ "${1:-}" = --legacy ]; then
  shift
  exec sh "$root/tools/build-legacy-release.sh" "$@"
fi
[ "$#" -le 1 ] || { echo 'Usage: build-release.sh [NEW_OUTPUT] | --legacy [OUTPUT]' >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo 'failed: Python 3 is required on the build host' >&2; exit 2; }
exec python3 "$root/tools/release/business_release.py" build "${1:-$root/release}"
