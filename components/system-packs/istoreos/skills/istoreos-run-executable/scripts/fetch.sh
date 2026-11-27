#!/bin/sh
# Verified download only. Execution, source choice and route policy are separate inputs.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
download="$here/../../kai-download-acceleration/scripts/accelerate.sh"
[ -f "$download" ] || download="$here/../../../../common/skills/kai-download-acceleration/scripts/accelerate.sh"
[ -f "$download" ] || download="$here/../../../../../system-packs/common/skills/kai-download-acceleration/scripts/accelerate.sh"
[ "$#" = 3 ] || { printf '%s\n' 'usage: fetch.sh HTTPS_URL ABSOLUTE_DESTINATION EXPECTED_SHA256' >&2; exit 2; }
case "$2" in /*) ;; *) printf '%s\n' 'an explicit absolute destination is required' >&2; exit 2 ;; esac
exec bash "$download" download "$1" "$2" "$3"
