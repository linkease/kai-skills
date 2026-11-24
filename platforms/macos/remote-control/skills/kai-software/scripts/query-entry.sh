#!/bin/sh
# Querying never prepares tools or changes a source.
set -u
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
bash_bin=${KAI_BASH_BIN:-$(command -v bash 2>/dev/null || :)}
if [ -z "$bash_bin" ] || ! "$bash_bin" --noprofile --norc -c '[ "$BASH_VERSINFO" -gt 3 ] || { [ "$BASH_VERSINFO" -eq 3 ] && [ "${BASH_VERSINFO[1]}" -ge 2 ]; }' 2>/dev/null; then
  printf '%s\n' '{"protocol":"software-query/v1","schemaVersion":1,"status":"blocked","reason":"compatible-bash-required","items":[],"effects":[]}'
  exit 21
fi
exec "$bash_bin" --noprofile --norc "$here/query.sh" "$@"
