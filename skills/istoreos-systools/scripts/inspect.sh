#!/bin/sh
set -eu

scope="${1:-all}"
systools_bin="${SYSTOOLS_BIN:-/usr/libexec/systools.sh}"

section() {
  printf '\n[%s]\n' "$1"
}

run_if_available() {
  command -v "$1" >/dev/null 2>&1 || return 0
  command "$@" 2>&1 || true
}

system_evidence() {
  section "system"
  [ ! -r /etc/openwrt_release ] || sed -n '1,20p' /etc/openwrt_release
  run_if_available ubus call system board
}

network_evidence() {
  section "network"
  run_if_available ip -brief address
  run_if_available ip route show
  run_if_available uci -q show network
  run_if_available uci -q show dhcp
}

storage_evidence() {
  section "storage"
  run_if_available df -h
  run_if_available lsblk
  if [ -x "$systools_bin" ]; then
    "$systools_bin" disk_power_mode 2>&1 || true
  else
    printf 'systools=unavailable (%s)\n' "$systools_bin"
  fi
}

store_evidence() {
  section "store"
  run_if_available opkg status luci-app-store
  if command -v is-opkg >/dev/null 2>&1; then
    printf 'is-opkg=available\n'
  else
    printf 'is-opkg=unavailable\n'
  fi
  [ ! -x /etc/init.d/tasks ] || /etc/init.d/tasks status 2>&1 || true
}

upgrade_evidence() {
  section "upgrade"
  run_if_available uname -a
  if [ -f /etc/apk/arch ]; then
    run_if_available apk list --installed --manifest 'kmod-*'
  elif [ -d /usr/lib/opkg/info ]; then
    grep -l '^Version: 0\.0\.0-r1$' /usr/lib/opkg/info/kmod-*.control 2>/dev/null || true
  fi
}

case "$scope" in
  network) system_evidence; network_evidence ;;
  storage) system_evidence; storage_evidence ;;
  store) system_evidence; store_evidence ;;
  upgrade) system_evidence; upgrade_evidence ;;
  all) system_evidence; network_evidence; storage_evidence; store_evidence; upgrade_evidence ;;
  *)
    printf 'usage: %s <network|storage|store|upgrade|all>\n' "$0" >&2
    exit 2
    ;;
esac
