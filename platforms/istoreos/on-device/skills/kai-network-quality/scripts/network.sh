#!/bin/sh
set -eu

mode="${1:-}"
[ "$#" -eq 0 ] || shift

fail() {
  printf 'failed: %s\n' "$*" >&2
  exit 2
}

blocked() {
  printf '{"schemaVersion":1,"status":"blocked","error":{"code":"%s","message":"%s","retryable":false}}\n' "$1" "$2"
  exit 4
}

select_jq() {
  jq_bin=
  for candidate in "${KAI_JQ_BIN:-}" "$(command -v jq 2>/dev/null || true)" "$HOME/.local/bin/jq"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" -ne '("abc"|test("^a")) and (({text:"中文"}|tojson|fromjson|.text)=="中文")' >/dev/null 2>&1; then jq_bin="$candidate"; break; fi
    [ -z "${KAI_JQ_BIN:-}" ] || blocked jq_unavailable 'The explicitly selected jq is incompatible; preserve it and prepare full jq through kai-tool-bootstrap'
  done
  [ -n "$jq_bin" ] || blocked jq_unavailable 'Prepare full jq through kai-tool-bootstrap on the selected target'
}

capture_machine() {
  seconds="$1"; output="$2"; shift 2
  # Scope file/time limits to the child. Never echo unvalidated human output or
  # credential-bearing native diagnostics into the machine result channel.
  if [ -n "$core_bin" ]; then
    (exec "$setsid_bin" "$core_bin" capture -o "$output" --max-bytes 2097152 --timeout "${seconds}s" -- "$fastnet_bin" "$@") >"$work/capture.log" 2>"$work/stderr" &
  else
    (ulimit -f 4096; exec "$setsid_bin" "$timeout_bin" -s TERM -k 1 "$seconds" "$fastnet_bin" "$@") >"$output" 2>"$work/stderr" &
  fi
  active_pid=$!
  result=0
  wait "$active_pid" || result=$?
  active_pid=
  return "$result"
}

cleanup() {
  if [ -n "${active_pid:-}" ]; then
    kill -s TERM -- "-$active_pid" 2>/dev/null || true
    sleep 1
    kill -s KILL -- "-$active_pid" 2>/dev/null || true
    wait "$active_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}

run_json() {
  seconds="${FASTNET_OPERATION_TIMEOUT_SECONDS:-120}"
  case "$seconds" in ''|*[!0-9]*) fail 'operation timeout must be integer seconds' ;; esac
  [ "$seconds" -ge 1 ] && [ "$seconds" -le 3600 ] || fail 'operation timeout must be 1..3600 seconds'
  code=0
  capture_machine "$seconds" "$work/result.json" "$@" || code=$?
  if ! "$jq_bin" -se --arg command "fastnet $required" 'length == 1 and (.[0] | .schemaVersion == 1 and .command == $command and (.status as $s | ["succeeded","partial","blocked","failed","canceled"] | index($s) != null) and (if .status == "succeeded" or .status == "partial" then has("result") else (.error.code | type == "string") end))' "$work/result.json" >/dev/null 2>&1; then
    blocked fastnet_invalid_result 'FastNet returned a menu, malformed result, timed out or exceeded the output limit; inspect its compatible machine release'
  fi
  if [ "$code" -eq 0 ] && ! "$jq_bin" -e '.status == "succeeded" or .status == "partial"' "$work/result.json" >/dev/null; then code=4; fi
  cat "$work/result.json"
  return "$code"
}

run_stream() {
  # JSONL progress and signal/cancellation remain native FastNet responsibilities
  # after the same bounded compatibility gate; do not buffer a long-lived stream.
  rm -rf "$work"
  trap - 0 HUP INT TERM
  exec "$fastnet_bin" "$@"
}

resolve_fastnet() {
  if [ -n "${FASTNET_BIN:-}" ]; then
    [ -x "$FASTNET_BIN" ] || fail "FASTNET_BIN is not executable"
    printf '%s\n' "$FASTNET_BIN"
    return
  fi
  command -v FastNet 2>/dev/null || command -v fastnet 2>/dev/null || true
}

require_fastnet() {
  fastnet_bin="$(resolve_fastnet)"
  [ -n "$fastnet_bin" ] || {
    printf '%s\n' '{"schemaVersion":1,"status":"blocked","error":{"code":"fastnet_unavailable","message":"install FastNet through kai-software for the selected target","retryable":false}}'
    exit 4
  }
  select_jq
  timeout_bin="$(command -v timeout 2>/dev/null || true)"
  core_bin="${KAI_ZSETUP_BIN:-$(command -v zsetup 2>/dev/null || true)}"
  if [ -z "$core_bin" ] && [ -x "$HOME/.local/bin/zsetup" ]; then core_bin="$HOME/.local/bin/zsetup"; fi
  [ -z "$core_bin" ] || [ -x "$core_bin" ] || blocked capture_unavailable 'The selected native zsetup is not executable; preserve it and prepare a compatible core'
  [ -n "$core_bin" ] || [ -n "$timeout_bin" ] || blocked timeout_unavailable 'Prepare native zsetup capture or Linux timeout for bounded machine execution'
  setsid_bin="$(command -v setsid 2>/dev/null || true)"
  [ -n "$setsid_bin" ] || blocked timeout_unavailable 'Linux setsid is required to cancel the FastNet process group safely'
  seconds="${FASTNET_PROBE_TIMEOUT_SECONDS:-5}"
  case "$seconds" in ''|*[!0-9]*) fail 'probe timeout must be integer seconds' ;; esac
  [ "$seconds" -ge 1 ] && [ "$seconds" -le 30 ] || fail 'probe timeout must be 1..30 seconds'
  umask 077
  work="$(mktemp -d "${TMPDIR:-/tmp}/kai-fastnet.XXXXXX")"
  trap 'cleanup' 0
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  capture_machine "$seconds" "$work/capabilities.json" capabilities --json || blocked fastnet_incompatible 'Install or upgrade FastNet through kai-software to a release supporting interaction schema 1; existing human commands are preserved'
  "$jq_bin" -se 'length == 1 and (.[0] | .schemaVersion == 1 and .command == "fastnet capabilities" and .status == "succeeded" and .result.product == "FastNet" and .result.interactionSchemaVersion == 1 and (.result.commands | type == "array"))' "$work/capabilities.json" >/dev/null 2>&1 || blocked fastnet_incompatible 'Install or upgrade FastNet through kai-software to a release supporting interaction schema 1; existing human commands are preserved'
  required="${1:-$mode}"
  if [ "$required" != capabilities ]; then
    "$jq_bin" -e --arg required "$required" 'any(.result.commands[]; (.name | split(" ")) as $parts | .name == $required or (($parts | length) == 2 and any($parts[1] | split("|")[]; ($parts[0] + " " + .) == $required)))' "$work/capabilities.json" >/dev/null || blocked fastnet_incompatible 'The installed FastNet machine interface does not support this operation; prepare a compatible release through kai-software'
  fi
}

require_confirmation() {
  [ "${KAIPLUS_CONFIRMED:-}" = "1" ] || {
    printf '%s\n' '{"schemaVersion":1,"status":"blocked","error":{"code":"confirmation_required","message":"explicit confirmation is required before contacting test endpoints","retryable":false}}'
    exit 8
  }
}

require_request() {
  [ "$#" -eq 1 ] || fail "$mode requires one request JSON file"
  [ -f "$1" ] && [ ! -L "$1" ] || fail "request must be a regular non-symlink file"
}

case "$mode" in
  inspect)
    [ "$#" -eq 0 ] || fail "inspect accepts no arguments"
    require_fastnet
    run_json inspect --json
    ;;
  capabilities)
    [ "$#" -eq 0 ] || fail "capabilities accepts no arguments"
    require_fastnet
    cat "$work/capabilities.json"
    ;;
  validate)
    require_request "$@"
    require_fastnet 'agent validate'
    run_json agent validate --request "$1" --json
    ;;
  diagnose)
    require_request "$@"
    require_confirmation
    require_fastnet 'agent execute'
    run_json agent execute --request "$1" --json
    ;;
  history)
    [ "$#" -ge 1 ] || fail "history requires a FastNet history subcommand"
    require_fastnet "history $1"
    run_json history "$@" --json
    ;;
  monitor)
    [ "$#" -ge 2 ] && [ "$#" -le 4 ] || fail "monitor requires REQUEST STORE and optional INTERVAL COUNT"
    request="$1"
    store="$2"
    interval="${3:-5m}"
    count="${4:-1}"
    [ -f "$request" ] && [ ! -L "$request" ] || fail "request must be a regular non-symlink file"
    case "$count" in ''|*[!0-9]*) fail "count must be numeric" ;; esac
    [ "$count" -le 1000 ] || fail "count must be at most 1000"
    require_confirmation
    require_fastnet 'monitor run'
    run_stream monitor run --request "$request" --store "$store" --interval "$interval" --count "$count" --confirmed --jsonl
    ;;
  lan-serve)
    [ "$#" -ge 2 ] && [ "$#" -le 3 ] || fail "lan-serve requires HOST:PORT TOKEN_FILE and optional TTL"
    addr="$1"
    token_file="$2"
    ttl="${3:-10m}"
    require_confirmation
    require_fastnet 'lan serve'
    run_stream lan serve --addr "$addr" --token-file "$token_file" --ttl "$ttl" --confirmed --jsonl
    ;;
  lan-test)
    [ "$#" -ge 2 ] && [ "$#" -le 4 ] || fail "lan-test requires HOST:PORT TOKEN_FILE and optional PARALLEL DURATION"
    addr="$1"
    token_file="$2"
    parallel="${3:-3}"
    duration="${4:-10}"
    [ -f "$token_file" ] && [ ! -L "$token_file" ] || fail "token must be a regular non-symlink file"
    case "$parallel:$duration" in *[!0-9:]*) fail "parallel and duration must be numeric" ;; esac
    require_confirmation
    require_fastnet 'lan test'
    run_json lan test --addr "$addr" --token-file "$token_file" --parallel "$parallel" --duration "$duration" --confirmed --json
    ;;
  measure)
    measure="${1:-}"
    [ "$#" -eq 0 ] || shift
    require_confirmation
    require_fastnet "measure $measure"
    case "$measure" in
      quick|multi|wan|nat|ipv6)
        [ "$#" -eq 0 ] || fail "$measure accepts no additional arguments"
        run_json measure "$measure" --confirmed --json
        ;;
      lan)
        [ "$#" -ge 1 ] && [ "$#" -le 2 ] || fail "lan requires HOST:PORT and optional PARALLEL"
        addr="$1"
        parallel="${2:-3}"
        case "$parallel" in ''|*[!0-9]*) fail "parallel must be numeric" ;; esac
        [ "$parallel" -ge 1 ] && [ "$parallel" -le 13 ] || fail "parallel must be between 1 and 13"
        if [ -n "${FASTNET_LAN_TOKEN:-}" ]; then
          export FASTNET_LAN_TOKEN
        fi
        run_json measure lan --addr "$addr" --parallel "$parallel" --confirmed --json
        ;;
      *) fail "unsupported measurement: $measure" ;;
    esac
    ;;
  *) fail "usage: network.sh inspect|capabilities|validate|diagnose|history|monitor|lan-serve|lan-test|measure" ;;
esac
