#!/bin/sh
set -eu
[ "${KAIPLUS_CONFIRMED:-}" = 1 ] || { echo 'blocked: dependency downloads and possible service start require authorization' >&2; exit 3; }
tool="${1:-}"
version="${2:-}"
work="${3:-}"
gateway="${4:-}"; port="${5:-}"
case "$tool" in pip|npm|go) ;; *) echo 'usage: smoke.sh pip|npm|go RESOLVED_VERSION NEW_ABSOLUTE_DIRECTORY' >&2; exit 2 ;; esac
printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo 'failed: a complete installed version is required' >&2; exit 2; }
case "$work" in /*) ;; *) echo 'failed: a new directory with an absolute path is required' >&2; exit 2 ;; esac
[ ! -e "$work" ] || { echo 'failed: a new directory is required; existing files will not be replaced' >&2; exit 2; }
if [ -n "$gateway" ] || [ -n "$port" ]; then
  [ "$#" = 5 ] && [ -r "$gateway" ] && [ -f "$gateway" ] || { echo 'failed: readable current-instance gateway log and actual TLS port are required' >&2; exit 2; }
  case "$port" in ''|*[!0-9]*) echo 'failed: numeric TLS port is required' >&2; exit 2 ;; esac
  [ "$port" -gt 0 ] && [ "$port" -le 65535 ] || exit 2
  command -v sha256sum >/dev/null 2>&1 || { echo 'failed: sha256sum is required to detect gateway log replacement' >&2; exit 4; }
else [ "$#" = 3 ] || { echo 'failed: unexpected arguments' >&2; exit 2; }; fi
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
if [ "${ISTORE_RUNTIME_ENTERED:-}" != 1 ]; then
  exec sh "$here/../../istoreos-mise-runtime/scripts/exec.sh" "$here/smoke.sh" "$@"
fi
. "$here/../../istoreos-mise-runtime/scripts/environment.sh"
runtime_environment_check
. "$here/../../istoreos-mise-runtime/scripts/result.sh"
umask 077
mkdir -p "$work"
cd "$work"
export MISE_AUTO_INSTALL=0 MISE_NOT_FOUND_AUTO_INSTALL=0
case "$tool" in pip) runtime=python ;; npm) runtime=node ;; go) runtime=go ;; esac
runtime_validation=not-run; client_validation=not-run; gateway_validation=pending
smoke_result() {
  code=$?
  trap - EXIT
  status=failed
  if [ "$code" = 0 ]; then status=partial; [ "$gateway_validation" != confirmed ] || status=passed; fi
  result_emit "$status" dependency-smoke "$code" tool "$tool" runtime "$runtime" version "$version" \
    environment_validation passed runtime_validation "$runtime_validation" client_validation "$client_validation" \
    gateway_validation "$gateway_validation" runtime_receipt "$work/runtime.json" client_log "$work/client.log" \
    gateway_log "$work/gateway.log" actual_tls_port "$port" >"$work/result.json"
  printf 'receipt=%s\n' "$work/result.json"
  cat "$work/result.json"
  exit "$code"
}
trap smoke_result EXIT
code=0
sh "$here/../../istoreos-mise-runtime/scripts/probe.sh" "$runtime" "$version" >"$work/runtime.json" || code=$?
if [ "$code" != 0 ]; then runtime_validation=failed; exit "$code"; fi
runtime_validation=passed
start=0
if [ -n "$gateway" ]; then
  start="$(wc -l <"$gateway")"
  prefix="$(head -n "$start" "$gateway" | sha256sum)"
fi
# Capture the actual adapter URL/port without persistent client configuration.
ks-cli --explain --json "$tool" install >"$work/plan.json"
status=0
run_demo() {
  case "$tool" in
    pip)
      mise exec "python@$version" -- python -m venv "$work/.venv" || return $?
      . "$work/.venv/bin/activate"
      # Do not inherit machine-specific indexes/TLS bypasses in a public smoke.
      unset PIP_INDEX_URL PIP_EXTRA_INDEX_URL PIP_TRUSTED_HOST
      export PIP_CONFIG_FILE=/dev/null PYTHONNOUSERSITE=1
      sh "$here/dependency.sh" pip "$version" -- install --no-cache-dir --disable-pip-version-check --only-binary=:all: -vv idna==3.10 || return $?
      python -c 'import idna; assert idna.__version__ == "3.10"; assert idna.encode("例子.测试") == b"xn--fsqu00a.xn--0zwm56d"; print("idna_import=ok")' || return $?
      sh "$here/dependency.sh" pip "$version" -- check || return $?
      ;;
    npm)
      cat >package.json <<'EOF'
{"name":"ks-npm-demo","version":"1.0.0","private":true,"dependencies":{"is-number":"7.0.0"}}
EOF
      sh "$here/dependency.sh" npm "$version" -- install --cache "$work/.npm-cache" --prefer-online --loglevel=http --ignore-scripts --no-audit --no-fund || return $?
      # Fresh client cache with the generated integrity-bearing lockfile.
      sh "$here/dependency.sh" npm "$version" -- ci --cache "$work/.npm-cache-ci" --prefer-online --loglevel=http --ignore-scripts --no-audit --no-fund || return $?
      mise exec "node@$version" -- node -e 'const n=require("is-number");if(!n(42)||n("abc"))process.exit(1);const l=require("./package-lock.json");if(!l.packages["node_modules/is-number"].integrity)process.exit(1);console.log("npm_dependency_run=ok integrity=present")' || return $?
      ;;
    go)
      export GOMODCACHE="$work/.gomodcache" GOCACHE="$work/.gocache" GOPATH="$work/.gopath" GOTOOLCHAIN=local GOENV=off
      unset GOPRIVATE GONOSUMDB GONOPROXY
      cat >go.mod <<'EOF'
module example.invalid/ks-go-demo

go 1.20

require github.com/google/uuid v1.6.0
EOF
      cat >main.go <<'EOF'
package main
import (
  "fmt"
  "github.com/google/uuid"
)
func main() {
  value, err := uuid.Parse("123e4567-e89b-12d3-a456-426614174000")
  if err != nil { panic(err) }
  fmt.Println(value.String())
}
EOF
      sh "$here/dependency.sh" go "$version" -- mod download -x github.com/google/uuid@v1.6.0 || return $?
      sh "$here/dependency.sh" go "$version" -- mod verify || return $?
      sh "$here/dependency.sh" go "$version" -- run . || return $?
      ;;
  esac
}
run_demo >"$work/client.log" 2>&1 || status=$?
cat "$work/client.log"
printf 'client_log=%s\nplan=%s\n' "$work/client.log" "$work/plan.json"
if [ "$status" != 0 ]; then
  client_validation=failed
  sh "$here/../../istoreos-mise-runtime/scripts/diagnose.sh" "$work/client.log" >&2
  exit "$status"
fi
client_validation=passed
if [ -n "$gateway" ]; then
  # Only lines appended during this invocation can supply gateway evidence.
  end="$(wc -l <"$gateway")"
  gateway_validation=insufficient-evidence
  if [ "$end" -ge "$start" ] && [ "$prefix" = "$(head -n "$start" "$gateway" | sha256sum)" ]; then
    awk -v start="$start" 'NR>start' "$gateway" >"$work/gateway.log"
    code=0
    sh "$here/evidence.sh" "$tool" "$work/client.log" "$work/gateway.log" "$port" >"$work/gateway.evidence" || code=$?
    cat "$work/gateway.evidence"
    if [ "$code" = 0 ]; then gateway_validation=confirmed
    elif grep -Fxq result=client-direct-observed "$work/gateway.evidence"; then gateway_validation=client-direct-observed; fi
    exit "$code"
  fi
  echo 'failed: gateway log rotated/truncated; recapture current-instance evidence' >&2
  exit 4
fi
printf 'client_validation=passed\ngateway_validation=pending-current-instance-logs\n'
