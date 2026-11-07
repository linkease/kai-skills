#!/bin/sh
set -eu

mode="${1:-}"
[ "$#" -eq 0 ] || shift

fail() {
  printf 'failed: %s\n' "$*" >&2
  exit 2
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
    exec "$fastnet_bin" inspect --json
    ;;
  capabilities)
    [ "$#" -eq 0 ] || fail "capabilities accepts no arguments"
    require_fastnet
    exec "$fastnet_bin" capabilities --json
    ;;
  validate)
    require_request "$@"
    require_fastnet
    exec "$fastnet_bin" agent validate --request "$1" --json
    ;;
  diagnose)
    require_request "$@"
    require_confirmation
    require_fastnet
    exec "$fastnet_bin" agent execute --request "$1" --json
    ;;
  history)
    [ "$#" -ge 1 ] || fail "history requires a FastNet history subcommand"
    require_fastnet
    exec "$fastnet_bin" history "$@"
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
    require_fastnet
    exec "$fastnet_bin" monitor run --request "$request" --store "$store" --interval "$interval" --count "$count" --confirmed --jsonl
    ;;
  lan-serve)
    [ "$#" -ge 2 ] && [ "$#" -le 3 ] || fail "lan-serve requires HOST:PORT TOKEN_FILE and optional TTL"
    addr="$1"
    token_file="$2"
    ttl="${3:-10m}"
    require_confirmation
    require_fastnet
    exec "$fastnet_bin" lan serve --addr "$addr" --token-file "$token_file" --ttl "$ttl" --confirmed --jsonl
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
    require_fastnet
    exec "$fastnet_bin" lan test --addr "$addr" --token-file "$token_file" --parallel "$parallel" --duration "$duration" --confirmed --json
    ;;
  measure)
    measure="${1:-}"
    [ "$#" -eq 0 ] || shift
    require_confirmation
    require_fastnet
    case "$measure" in
      quick|multi|wan|nat|ipv6)
        [ "$#" -eq 0 ] || fail "$measure accepts no additional arguments"
        exec "$fastnet_bin" measure "$measure" --confirmed --json
        ;;
      lan)
        [ "$#" -ge 1 ] && [ "$#" -le 2 ] || fail "lan requires HOST:PORT and optional PARALLEL"
        addr="$1"
        parallel="${2:-3}"
        case "$parallel" in ''|*[!0-9]*) fail "parallel must be numeric" ;; esac
        [ "$parallel" -ge 1 ] && [ "$parallel" -le 13 ] || fail "parallel must be between 1 and 13"
        if [ -n "${FASTNET_LAN_TOKEN:-}" ]; then
          exec env FASTNET_LAN_TOKEN="$FASTNET_LAN_TOKEN" "$fastnet_bin" measure lan --addr "$addr" --parallel "$parallel" --confirmed --json
        fi
        exec "$fastnet_bin" measure lan --addr "$addr" --parallel "$parallel" --confirmed --json
        ;;
      *) fail "unsupported measurement: $measure" ;;
    esac
    ;;
  *) fail "usage: network.sh inspect|capabilities|validate|diagnose|history|monitor|lan-serve|lan-test|measure" ;;
esac
