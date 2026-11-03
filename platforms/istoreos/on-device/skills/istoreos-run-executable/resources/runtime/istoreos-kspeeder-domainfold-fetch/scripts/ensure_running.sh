#!/bin/sh
set -eu

root="${ISTOREOS_ROOT:-}"
root="${root%/}"
service="$root/etc/init.d/istoreenhance"

is_running() {
  if command -v pidof >/dev/null 2>&1; then
    pidof iStoreEnhance >/dev/null 2>&1 && return 0
  fi
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -x iStoreEnhance >/dev/null 2>&1 && return 0
  fi
  return 1
}

if is_running; then
  echo "ok: iStoreEnhance already running" >&2
  exit 0
fi

if [ ! -x "$service" ]; then
  echo "need-confirmation: service script not found: $service" >&2
  echo "please confirm how iStoreEnhance is managed on your iStoreOS/OpenWrt." >&2
  exit 2
fi

if [ "${KAIPLUS_CONFIRMED:-}" != "1" ]; then
  echo "need-confirmation: enabling and starting iStoreEnhance changes startup state; rerun with KAIPLUS_CONFIRMED=1 after user confirmation" >&2
  exit 2
fi

echo "action: enable service (best-effort): $service enable" >&2
"$service" enable >/dev/null 2>&1 || true

echo "action: start service: $service start" >&2
"$service" start >/dev/null 2>&1 || "$service" restart >/dev/null 2>&1 || true

if is_running; then
  echo "ok: iStoreEnhance running" >&2
  exit 0
fi

echo "failed: iStoreEnhance still not running." >&2
echo "diagnostics to run:" >&2
echo "- $service status" >&2
echo "- logread | tail -n 200" >&2
exit 1
