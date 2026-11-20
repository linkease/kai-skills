#!/bin/bash
# Native KAIPlus Provider client; no package-manager Shell construction.
set -euo pipefail
fail() { printf '%s\n' '{"schema":"homebrew-market-client/v1","status":"blocked","reason":"selected target requires macOS, a compatible native KAIPlus CLI and its explicit loopback Provider endpoint; no controller or Formula-only fallback"}' >&2; exit 1; }
if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' 'homebrew-market.sh contract|detect|search|info|installed|outdated|sources|files|verify|tasks|plan [typed CLI options]' 'plan reads one typed JSON object from stdin; reviewPath opens the software page. No apply/confirm command.'; exit 0
fi
[[ "$(uname -s)" == Darwin ]] || fail
client=${KAI_SOFTWARE_CLI_BIN:-}
case "$client" in /*) [[ -f "$client" && -x "$client" ]] || fail ;; *) fail ;; esac
contract=$("$client" software contract) || fail
[[ "$contract" == *'"schema":"homebrew-market-cli/v1"'* ]] || fail
[[ "${1:-}" != contract ]] || { printf '%s\n' "$contract"; exit 0; }
case "${1:-}" in detect|search|info|installed|outdated|sources|files|verify|tasks|plan) ;; *) fail ;; esac
[[ -n "${KAI_SOFTWARE_API:-}" ]] || fail
exec "$client" software "$@" --endpoint "$KAI_SOFTWARE_API"
