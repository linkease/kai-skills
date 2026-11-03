#!/bin/sh
set -eu
runtime="${1:-}"; version="${2:-}"
case "$runtime" in python|node|go) ;; *) echo 'usage: probe.sh python|node|go RESOLVED_VERSION' >&2; exit 2 ;; esac
printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo 'failed: a complete installed version is required' >&2; exit 2; }
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
. "$here/result.sh"
if [ "${ISTORE_RUNTIME_ENTERED:-}" != 1 ]; then
  output="$(mktemp "${TMPDIR:-/tmp}/istore-probe.XXXXXX")"
  trap 'rm -f "$output"' EXIT HUP INT TERM
  code=0
  sh "$here/exec.sh" "$here/probe.sh" "$runtime" "$version" >"$output" || code=$?
  if [ -s "$output" ]; then cat "$output"; else
    result_emit failed runtime-probe "$code" runtime "$runtime" version "$version" environment_validation failed runtime_validation not-run gateway_validation not-applicable
  fi
  exit "$code"
fi
. "$here/environment.sh"
runtime_environment_check
export MISE_AUTO_INSTALL=0 MISE_NOT_FOUND_AUTO_INSTALL=0
log="$(mktemp "${TMPDIR:-/tmp}/istore-probe-log.XXXXXX")"
trap 'rm -f "$log"' EXIT HUP INT TERM
code=0; sdk=""
sdk="$(mise where "$runtime@$version" 2>"$log")" || code=$?
if [ "$code" = 0 ]; then sh "$here/verify.sh" "$runtime" "$version" >>"$log" 2>&1 || code=$?; fi
cat "$log" >&2
status=passed; validation=passed
if [ "$code" != 0 ]; then status=failed; validation=failed; fi
result_emit "$status" runtime-probe "$code" runtime "$runtime" version "$version" \
  environment_validation passed runtime_validation "$validation" gateway_validation not-applicable \
  home "$HOME" mise_data_dir "${MISE_DATA_DIR:-}" mise_cache_dir "${MISE_CACHE_DIR:-}" mise_config_dir "${MISE_CONFIG_DIR:-}" sdk_path "$sdk"
exit "$code"
