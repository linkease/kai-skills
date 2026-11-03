#!/bin/sh
set -eu

mode="${1:-auto}"
subject="${2:-}"
root="${ISTOREOS_ROOT:-}"
root="${root%/}"
limit="${ISTOREOS_EVIDENCE_MAX_BYTES:-8192}"

need() {
  echo "$*" >&2
  exit 2
}

valid_identifier() {
  value="$1"
  case "$value" in
    [A-Za-z0-9]*) ;;
    *) return 1 ;;
  esac
  case "$value" in
    *[!A-Za-z0-9._+-]*|*..*) return 1 ;;
  esac
  return 0
}

redact() {
  sed -E \
    -e "s#((password|passwd|token|secret|apikey|api_key|access_key|private_key|psk|auth|authorization)[[:space:]]*=[[:space:]]*)('[^']*'|\"[^\"]*\"|[^[:space:]]+)#\\1'***'#gI" \
    -e "s#([?&](password|passwd|token|secret|apikey|api_key|access_key|private_key|psk|auth|authorization)=)[^&[:space:]]+#\\1***#gI" \
    -e 's#(://)[^/@[:space:]]+:[^/@[:space:]]+@#\1***:***@#g'
}

section() {
  printf '\n[%s]\n' "$1"
}

command_state() {
  name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    printf 'tool.%s=available\n' "$name"
  else
    printf 'tool.%s=missing\n' "$name"
  fi
}

case "$mode" in
  auto|network|storage|service|package|docker|kai) ;;
  *) need 'supported modes: auto, network, storage, service, package, docker, kai' ;;
esac
case "$mode" in
  service|package)
    [ -n "$subject" ] || need "$mode mode requires a service or package identifier"
    valid_identifier "$subject" || need 'invalid identifier: traversal and path characters are not allowed'
    ;;
esac

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT HUP INT TERM
{
  echo 'evidence_version=1'
  echo "mode=$mode"
  echo "subject=$subject"
  echo "observed_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"
  echo 'source=current-device'
  echo 'confidence=observed'
  echo 'read_only=true'

  section platform
  [ ! -r "$root/etc/openwrt_release" ] || sed -n '1,30p' "$root/etc/openwrt_release"
  uname -a 2>/dev/null || true

  case "$mode" in
    auto)
      section resources
      uptime 2>/dev/null || true
      df -P -k 2>/dev/null | head -n 24 || true
      [ ! -r "$root/proc/meminfo" ] || sed -n '1,12p' "$root/proc/meminfo"
      section capabilities
      for name in is-opkg opkg apk mise-exec mise ks-cli uci ubus logread docker FastNet iStoreEnhance; do command_state "$name"; done
      ;;
    network)
      section addresses
      ip addr show 2>/dev/null | head -n 80 || true
      section routes
      ip route show 2>/dev/null | head -n 40 || true
      ip -6 route show 2>/dev/null | head -n 40 || true
      section dns
      [ ! -r "$root/etc/resolv.conf" ] || sed -n '1,30p' "$root/etc/resolv.conf"
      ;;
    storage)
      section filesystems
      df -P -k 2>/dev/null | head -n 32 || true
      section mounts
      mount 2>/dev/null | head -n 40 || true
      ;;
    service)
      init="$root/etc/init.d/$subject"
      section service
      echo "init=$init"
      if [ -x "$init" ]; then "$init" status 2>&1 | head -n 80 || true; else echo 'status=init-missing'; fi
      section recent_logs
      if command -v logread >/dev/null 2>&1; then logread 2>/dev/null | grep -i -- "$subject" | tail -n 40 || true; else echo 'logread=missing'; fi
      ;;
    package)
      section package
      here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
      pkg="$here/../resources/runtime/istoreos-package-manager/scripts/package.sh"
      ISTORE_SYSTEM_ROOT="$root" sh "$pkg" detect 2>&1 || true
      ISTORE_SYSTEM_ROOT="$root" sh "$pkg" installed "$subject" 2>&1 | head -n 80 || true
      ISTORE_SYSTEM_ROOT="$root" sh "$pkg" files "$subject" 2>&1 | head -n 120 || true
      ;;
    docker)
      section daemon
      [ ! -x "$root/etc/init.d/dockerd" ] || "$root/etc/init.d/dockerd" status 2>&1 | head -n 60 || true
      section containers
      if command -v docker >/dev/null 2>&1; then
        docker ps --all --format '{{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null | head -n 60 || true
        docker info --format 'DockerRootDir={{.DockerRootDir}} Driver={{.Driver}}' 2>/dev/null || true
      else
        echo 'docker=missing'
      fi
      ;;
    kai)
      section process
      ps 2>/dev/null | grep -E '[k]aiplus(_bin)?' | head -n 20 || true
      section config
      if command -v uci >/dev/null 2>&1; then uci -q show kaiplus 2>/dev/null | head -n 100 || true; else echo 'uci=missing'; fi
      section listeners
      if command -v ss >/dev/null 2>&1; then ss -lntup 2>/dev/null | head -n 80 || true; elif command -v netstat >/dev/null 2>&1; then netstat -lntup 2>/dev/null | head -n 80 || true; fi
      ;;
  esac
} | redact >"$tmp"

bytes="$(wc -c <"$tmp" | tr -d ' ')"
case "$limit" in ''|*[!0-9]*) limit=8192 ;; esac
if [ "$bytes" -le "$limit" ]; then
  cat "$tmp"
else
  head -c "$((limit - 40))" "$tmp"
  printf '\ntruncated=true original_bytes=%s\n' "$bytes"
fi
