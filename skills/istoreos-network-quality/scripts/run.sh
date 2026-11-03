#!/bin/sh
set -eu

mode="${1:-}"
[ "$#" -eq 0 ] || shift
requested_bin="${FASTNET_BIN:-/usr/sbin/FastNet}"

usage() {
  cat >&2 <<'EOF'
Usage:
  run.sh quick
  run.sh wan [numeric-server-id]
  run.sh multi
  run.sh nat
  run.sh ipv6
  run.sh lan <host:port> [parallel]
EOF
}

fail() {
  printf 'failed: %s\n' "$*" >&2
  exit 2
}

require_no_args() {
  [ "$#" -eq 0 ] || { usage; fail "$mode accepts no arguments"; }
}

resolve_fastnet() {
  if [ -x "$requested_bin" ]; then
    printf '%s\n' "$requested_bin"
    return 0
  fi
  command -v FastNet 2>/dev/null || true
}

require_confirmation() {
  [ "${KAIPLUS_CONFIRMED:-}" = "1" ] || {
    printf 'blocked: explicit user confirmation is required before running a network test\n' >&2
    exit 3
  }
}

run_fastnet() {
  default_timeout="$1"
  shift
  timeout_seconds="${FASTNET_TIMEOUT:-$default_timeout}"
  case "$timeout_seconds" in
    ''|*[!0-9]*) fail "FASTNET_TIMEOUT must be a positive integer" ;;
  esac
  [ "$timeout_seconds" -gt 0 ] || fail "FASTNET_TIMEOUT must be a positive integer"

  fastnet_bin="$(resolve_fastnet)"
  [ -n "$fastnet_bin" ] || {
    printf 'failed: FastNet is not installed; install app-meta-fastnet through istoreos-package-manager\n' >&2
    exit 4
  }

  require_confirmation
  if command -v timeout >/dev/null 2>&1; then
    exec timeout "$timeout_seconds" "$fastnet_bin" "$@"
  fi
  exec "$fastnet_bin" "$@"
}

case "$mode" in
  quick)
    require_no_args "$@"
    run_fastnet 180 quick
    ;;
  wan)
    [ "$#" -le 1 ] || { usage; fail "wan accepts at most one server id"; }
    server_id="${1:-}"
    if [ -n "$server_id" ]; then
      case "$server_id" in
        *[!0-9]*) fail "server id must be numeric" ;;
      esac
      [ "$server_id" -gt 0 ] || fail "server id must be greater than zero"
      run_fastnet 180 speedtest_one --json --server "$server_id"
    fi
    run_fastnet 180 speedtest_one --json
    ;;
  multi)
    require_no_args "$@"
    run_fastnet 180 multi-stream
    ;;
  nat)
    require_no_args "$@"
    run_fastnet 60 nat
    ;;
  ipv6)
    require_no_args "$@"
    run_fastnet 90 ipv6
    ;;
  lan)
    [ "$#" -ge 1 ] && [ "$#" -le 2 ] || { usage; fail "lan requires host:port and optional parallel"; }
    addr="$1"
    parallel="${2:-3}"
    case "$addr" in
      ''|*[!A-Za-z0-9._:-]*) fail "LAN address must use host:port without spaces or URL syntax" ;;
      *:*) ;;
      *) fail "LAN address must include a port" ;;
    esac
    port="${addr##*:}"
    host="${addr%:*}"
    [ -n "$host" ] || fail "LAN host is required"
    case "$host" in
      *:*) fail "LAN address must use an IPv4 address or hostname with one port separator" ;;
      *[!A-Za-z0-9._-]*) fail "LAN host contains unsupported characters" ;;
    esac
    case "$port" in
      ''|*[!0-9]*) fail "LAN port must be numeric" ;;
    esac
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || fail "LAN port must be between 1 and 65535"
    case "$parallel" in
      ''|*[!0-9]*) fail "parallel must be numeric" ;;
    esac
    [ "$parallel" -ge 1 ] && [ "$parallel" -le 13 ] || fail "parallel must be between 1 and 13"

    if [ -n "${FASTNET_LAN_TOKEN:-}" ]; then
      run_fastnet 90 homebox_cli --addr "$addr" --parallel "$parallel" --token "$FASTNET_LAN_TOKEN"
    fi
    run_fastnet 90 homebox_cli --addr "$addr" --parallel "$parallel"
    ;;
  '')
    usage
    exit 2
    ;;
  *)
    usage
    fail "unsupported mode: $mode"
    ;;
esac
