#!/bin/sh
set -eu
json=0
if [ "${1:-}" = --json ]; then json=1; shift; fi
tool="${1:-}"
client="${2:-}"
gateway="${3:-}"
port="${4:-}"
case "$tool" in pip|npm|go) ;; *) echo 'usage: evidence.sh pip|npm|go CLIENT_LOG GATEWAY_LOG ACTUAL_TLS_PORT' >&2; exit 2 ;; esac
[ -f "$client" ] && [ -f "$gateway" ] || { echo 'failed: both current-run logs are required' >&2; exit 2; }
case "$port" in ''|*[!0-9]*) echo 'failed: actual numeric TLS port is required' >&2; exit 2 ;; esac
[ "$port" -gt 0 ] && [ "$port" -le 65535 ] || exit 2
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
if [ "$json" = 0 ]; then exec awk -v tool="$tool" -v port="$port" -f "$here/../data/gateway-evidence.awk" "$client" "$gateway"; fi
. "$here/../../istoreos-mise-runtime/scripts/result.sh"
output="$(mktemp "${TMPDIR:-/tmp}/istore-evidence.XXXXXX")"
trap 'rm -f "$output"' EXIT HUP INT TERM
code=0
awk -v tool="$tool" -v port="$port" -f "$here/../data/gateway-evidence.awk" "$client" "$gateway" >"$output" || code=$?
status=failed; validation=insufficient-evidence
if [ "$code" = 0 ]; then status=passed; validation=confirmed
elif grep -Fxq result=client-direct-observed "$output"; then validation=client-direct-observed; fi
result_emit "$status" gateway-evidence "$code" tool "$tool" gateway_validation "$validation" actual_tls_port "$port" \
  gateway_metadata "$(sed -n 's/^gateway_metadata=//p' "$output")" gateway_artifact "$(sed -n 's/^gateway_artifact=//p' "$output")"
exit "$code"
