#!/bin/sh
# Legacy name retained for explicitly selected observations; no intent classification.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
system_scripts="$here/../../kai-system-information/scripts"
[ -f "$system_scripts/inspect.sh" ] || system_scripts="$here/../../../../common/skills/kai-system-information/scripts"
target=${ZSETUP_TASK_TARGET_ID:-local}
case "${1:-auto}" in
  auto) exec sh "$system_scripts/inspect.sh" --target-id "$target" --sections os,tools ;;
  network) exec sh "$system_scripts/observe.sh" --target-id "$target" --source "${2:-addresses}" ;;
  storage) exec sh "$system_scripts/observe.sh" --target-id "$target" --source filesystems ;;
  service) exec sh "$here/../../istoreos-service-manager/scripts/inspect.sh" --target-id "$target" --service "${2:?an explicit service identifier is required}" ;;
  docker) exec sh "$here/../../istoreos-service-manager/scripts/inspect.sh" --target-id "$target" --service dockerd ;;
  kai) exec sh "$here/../../istoreos-service-manager/scripts/inspect.sh" --target-id "$target" --service kaiplus ;;
  package) exec sh "$here/../../istoreos-package-manager/scripts/package.sh" installed "${2:?an explicit package identity is required}" ;;
  *) printf '%s\n' 'unsupported observation scope' >&2; exit 2 ;;
esac
