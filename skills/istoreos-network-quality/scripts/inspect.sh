#!/bin/sh
set -eu

requested_bin="${FASTNET_BIN:-/usr/sbin/FastNet}"
fastnet_init="${FASTNET_INIT:-/etc/init.d/fastnet}"

section() {
  printf '\n[%s]\n' "$1"
}

run_if_available() {
  command -v "$1" >/dev/null 2>&1 || return 0
  command "$@" 2>&1 || true
}

resolve_fastnet() {
  if [ -x "$requested_bin" ]; then
    printf '%s\n' "$requested_bin"
    return 0
  fi
  command -v FastNet 2>/dev/null || true
}

section system
[ ! -r /etc/openwrt_release ] || sed -n '1,20p' /etc/openwrt_release
run_if_available uname -m
[ ! -r /proc/loadavg ] || { printf 'loadavg='; sed -n '1p' /proc/loadavg; }

section network
if command -v ip >/dev/null 2>&1; then
  ip -brief address 2>/dev/null || ip address show 2>&1 || true
  ip route show 2>&1 || true
  ip -6 route show default 2>&1 || true
fi
if command -v ubus >/dev/null 2>&1; then
  ubus call network.interface.wan status 2>&1 || true
  ubus call network.interface.wan6 status 2>&1 || true
fi

section fastnet
fastnet_bin="$(resolve_fastnet)"
if [ -z "$fastnet_bin" ]; then
  printf 'fastnet=unavailable\n'
  printf 'next_action=install app-meta-fastnet through istoreos-package-manager\n'
  exit 0
fi

printf 'fastnet=available\n'
printf 'binary=%s\n' "$fastnet_bin"
printf 'version='
"$fastnet_bin" version 2>&1 || true

if command -v opkg >/dev/null 2>&1; then
  opkg status fastnet 2>&1 | sed -n '1,20p' || true
fi

if [ -x "$fastnet_init" ]; then
  printf 'service_init=available\n'
  "$fastnet_init" status 2>&1 || true
else
  printf 'service_init=unavailable\n'
fi

if command -v uci >/dev/null 2>&1; then
  enabled="$(uci -q get 'fastnet.@fastnet[0].enabled' 2>/dev/null || true)"
  port="$(uci -q get 'fastnet.@fastnet[0].port' 2>/dev/null || true)"
  logger="$(uci -q get 'fastnet.@fastnet[0].logger' 2>/dev/null || true)"
  token="$(uci -q get 'fastnet.@fastnet[0].token' 2>/dev/null || true)"
  printf 'enabled=%s\n' "${enabled:-unknown}"
  printf 'port=%s\n' "${port:-unknown}"
  printf 'logger=%s\n' "${logger:-unknown}"
  if [ -n "$token" ]; then
    printf 'token_configured=yes\n'
  else
    printf 'token_configured=no\n'
  fi
fi

if command -v pidof >/dev/null 2>&1; then
  if pidof FastNet >/dev/null 2>&1; then
    printf 'process=running\n'
  else
    printf 'process=stopped\n'
  fi
fi
