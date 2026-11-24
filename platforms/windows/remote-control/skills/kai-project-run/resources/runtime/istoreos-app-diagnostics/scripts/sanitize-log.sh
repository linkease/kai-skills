#!/bin/sh
set -eu

max_bytes="${ISTORE_DIAG_LOG_MAX_BYTES:-8192}"
case "$max_bytes" in ''|*[!0-9]*) echo "invalid ISTORE_DIAG_LOG_MAX_BYTES" >&2; exit 2 ;; esac

# Logs are untrusted input. Normalize terminal output, redact common credentials,
# collapse adjacent duplicate rows, and cap what can reach the model context.
LC_ALL=C tr '\r' '\n' |
  sed \
    -e 's/\[[0-9;?]*[ -\/]*[@-~]//g' \
    -E \
    -e 's#([Aa]uthorization:[[:space:]]*(Bearer|Basic))[[:space:]]+[^[:space:]]+#\1 [REDACTED]#g' \
    -e 's#((api[_-]?key|access[_-]?token|refresh[_-]?token|token|password|passwd|secret)[[:space:]]*[:=][[:space:]]*)[^[:space:]]+#\1[REDACTED]#g' \
    -e 's#(https?://)[^/@[:space:]]+:[^/@[:space:]]+@#\1[REDACTED]@#g' |
  sed -E 's#(https?://[^?[:space:]]+)\?[^[:space:]]+#\1?[REDACTED]#g' |
  sed -E \
    -e 's#.*([Ii][Gg][Nn][Oo][Rr][Ee].*([Pp][Rr][Ee][Vv][Ii][Oo][Uu][Ss]|[Ss][Yy][Ss][Tt][Ee][Mm]).*[Ii][Nn][Ss][Tt][Rr][Uu][Cc][Tt][Ii][Oo][Nn]).*#[UNTRUSTED_INSTRUCTION_REDACTED]#' \
    -e 's#.*([Pp][Rr][Ii][Nn][Tt]|[Ss][Hh][Oo][Ww]|[Rr][Ee][Vv][Ee][Aa][Ll]).*/etc/(shadow|passwd).*#[UNTRUSTED_INSTRUCTION_REDACTED]#' \
    -e 's#.*([Rr][Ee][Vv][Ee][Aa][Ll]|[Ee][Xx][Pp][Oo][Ss][Ee]).*([Ss][Yy][Ss][Tt][Ee][Mm][[:space:]_-]*[Pp][Rr][Oo][Mm][Pp][Tt]|[Ss][Ee][Cc][Rr][Ee][Tt]).*#[UNTRUSTED_INSTRUCTION_REDACTED]#' |
  awk 'BEGIN { previous = "" } { if ($0 != previous || $0 == "") print; previous = $0 }' |
  head -c "$max_bytes"
