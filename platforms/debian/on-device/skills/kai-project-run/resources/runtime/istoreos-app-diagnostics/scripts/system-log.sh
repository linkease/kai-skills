#!/bin/sh
set -eu

app="${1:-}"
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
case "$app" in [A-Za-z0-9][A-Za-z0-9._+-]*) ;; *) echo 'invalid app id' >&2; exit 2 ;; esac

max_lines="${ISTORE_DIAG_SYSTEM_LOG_MAX_LINES:-120}"
max_bytes="${ISTORE_DIAG_SYSTEM_LOG_MAX_BYTES:-8192}"
case "$max_lines:$max_bytes" in *[!0-9:]*) echo 'invalid system log limit' >&2; exit 2 ;; esac

if [ -n "${ISTORE_DIAG_SYSTEM_LOG_FILE:-}" ]; then
  [ -r "$ISTORE_DIAG_SYSTEM_LOG_FILE" ] || exit 0
  input="$ISTORE_DIAG_SYSTEM_LOG_FILE"
else
  command -v logread >/dev/null 2>&1 || exit 0
  input="$(mktemp)"
  trap 'rm -f "$input"' EXIT HUP INT TERM
  logread >"$input" 2>/dev/null || :
fi

# System logs are requested only after precise task/device evidence proved
# insufficient. Filter before sanitizing so unrelated system history never
# enters the model context.
grep -Ei "(^|[^A-Za-z0-9._+-])($app|app-meta-$app)([^A-Za-z0-9._+-]|$)" "$input" 2>/dev/null |
  tail -n "$max_lines" |
  ISTORE_DIAG_LOG_MAX_BYTES="$max_bytes" "$script_dir/sanitize-log.sh"
