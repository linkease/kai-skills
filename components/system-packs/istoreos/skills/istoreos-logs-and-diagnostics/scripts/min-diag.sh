#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
system_scripts="$here/../../kai-system-information/scripts"
[ -f "$system_scripts/inspect.sh" ] || system_scripts="$here/../../../../common/skills/kai-system-information/scripts"
[ -f "$system_scripts/inspect.sh" ] || system_scripts="$here/../../../../../system-packs/common/skills/kai-system-information/scripts"
case "${1:-base}" in
  docker) exec sh "$here/../../istoreos-service-manager/scripts/inspect.sh" --target-id "${ZSETUP_TASK_TARGET_ID:-local}" --service dockerd ;;
  base) exec sh "$system_scripts/inspect.sh" --target-id "${ZSETUP_TASK_TARGET_ID:-local}" --sections os,tools ;;
  pkg) exec sh "$here/../../istoreos-package-manager/scripts/package.sh" detect ;;
  disk) exec sh "$system_scripts/observe.sh" --target-id "${ZSETUP_TASK_TARGET_ID:-local}" --source filesystems ;;
  *) printf '%s\n' 'unsupported scope: base, disk, docker; package facts use the explicit package query interface' >&2; exit 2 ;;
esac
