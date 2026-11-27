#!/bin/sh
# Query the explicitly selected path; Docker API/UCI/registration facts stay separate.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
storage="$here/../../kai-storage-files/scripts/usage.sh"
[ -f "$storage" ] || storage="$here/../../../../common/skills/kai-storage-files/scripts/usage.sh"
[ -f "$storage" ] || storage="$here/../../../../../system-packs/common/skills/kai-storage-files/scripts/usage.sh"
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { printf '%s\n' 'usage: check_space.sh ABSOLUTE_EXISTING_DIRECTORY [MIN_FREE_BYTES]' >&2; exit 2; }
exec bash "$storage" storage "$1" "${2:-${DOCKER_MIN_FREE_BYTES:-2147483648}}"
