#!/bin/sh
set -eu

action="${1:-}"
argument="${2:-}"
systools_bin="${SYSTOOLS_BIN:-/usr/libexec/systools.sh}"

[ "${KAIPLUS_CONFIRMED:-}" = "1" ] || {
  echo "blocked: explicit user confirmation is required" >&2
  exit 3
}

[ -x "$systools_bin" ] || {
  echo "failed: iStoreOS system tools are not installed" >&2
  exit 4
}

case "$action" in
  ipv6_pd|ipv6_relay|ipv6_nat|ipv6_half|ipv6_off|istore-reinstall|reinstall_incompatible_kmods)
    [ -z "$argument" ] || { echo "failed: this action accepts no argument" >&2; exit 2; }
    exec "$systools_bin" "$action"
    ;;
  *)
    echo "failed: action is not in the KaiPlus reviewed allowlist" >&2
    exit 2
    ;;
esac
