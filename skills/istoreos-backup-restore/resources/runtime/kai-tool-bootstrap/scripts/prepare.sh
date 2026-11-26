#!/bin/sh
# First entry: POSIX shell only. No jq or zsetup required to locate Bash.
set -u
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
action=${1:-probe}
case "$action" in probe|plan|ensure) ;; *) exit 2 ;; esac
bash_bin=${KAI_BASH_BIN:-$(command -v bash 2>/dev/null || :)}
if [ -n "$bash_bin" ] && "$bash_bin" --noprofile --norc -c \
    '[ "$BASH_VERSINFO" -gt 3 ] || { [ "$BASH_VERSINFO" -eq 3 ] && [ "${BASH_VERSINFO[1]}" -ge 2 ]; }' 2>/dev/null; then
    exec "$bash_bin" --noprofile --norc "$here/prepare-runtime.sh" "$action"
fi
if [ -n "${KAI_BASH_BIN:-}" ]; then
    printf '%s\n' '{"schemaVersion":1,"protocol":"kai-runtime/v1","ready":false,"status":"blocked","stage":"bash","reason":"selected-bash-incompatible","exitCode":17}'
    exit 17
fi
/bin/sh "$here/prepare-bash.sh" "$action" || exit $?
if [ "$action" = ensure ]; then
    bash_bin=$(command -v bash 2>/dev/null || :)
    [ -n "$bash_bin" ] || exit 18
    exec "$bash_bin" --noprofile --norc "$here/prepare-runtime.sh" "$action"
fi
