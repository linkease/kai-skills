#!/bin/sh
set -eu
root="${LINKEASE_SKILLS_ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)}"
exec python3 "$root/tools/business/generate.py" --output "${1:-$root}"
