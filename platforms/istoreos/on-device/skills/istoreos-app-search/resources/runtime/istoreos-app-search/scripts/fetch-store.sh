#!/bin/sh
set -eu

api="${ISTORE_STORE_API:-https://istore.istoreos.com/api/store/list}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
response="$tmp/store.json"

uci_value() {
  if command -v uci >/dev/null 2>&1; then uci -q get "$1" 2>/dev/null || :; fi
}

if [ -n "${ISTORE_STORE_RESPONSE_FILE:-}" ]; then
  [ -r "$ISTORE_STORE_RESPONSE_FILE" ] || { echo 'store response fixture is not readable' >&2; exit 1; }
  cp "$ISTORE_STORE_RESPONSE_FILE" "$response"
else
  super_arch="${ISTORE_STORE_SUPER_ARCH:-$(uci_value istore.istore.super_arch)}"
  hide_docker="${ISTORE_STORE_HIDE_DOCKER:-$(uci_value istore.istore.hide_docker)}"
  ignore_arch="${ISTORE_STORE_IGNORE_ARCH:-$(uci_value istore.istore.ignore_arch)}"
  channel="${ISTORE_STORE_CHANNEL:-$(uci_value istore.istore.channel)}"
  model_arch="${ISTORE_STORE_MODEL_ARCH:-}"
  device_id="${ISTORE_STORE_DEVICE_ID:-}"

  [ "$hide_docker" = 1 ] && hide_docker=true || hide_docker=false
  [ "$ignore_arch" = 1 ] && ignore_arch=true || ignore_arch=false
  if [ -r /etc/.app_store.id ] && command -v jsonfilter >/dev/null 2>&1; then
    [ -n "$model_arch" ] || model_arch="$(jsonfilter -q -i /etc/.app_store.id -e '@.arch' 2>/dev/null || :)"
    [ -n "$device_id" ] || device_id="$(jsonfilter -q -i /etc/.app_store.id -e '@.uid' 2>/dev/null || :)"
  fi

  command -v curl >/dev/null 2>&1 || { echo 'curl is required for the iStore catalog' >&2; exit 1; }
  curl -fsSG --max-time "${ISTORE_STORE_TIMEOUT:-20}" "$api" \
    --data-urlencode tag=default \
    --data-urlencode sort=default \
    --data-urlencode search= \
    --data-urlencode limit=1000 \
    --data-urlencode offset=0 \
    --data-urlencode "hide_docker=$hide_docker" \
    --data-urlencode "ignore_arch=$ignore_arch" \
    --data-urlencode "super_arch=$super_arch" \
    --data-urlencode "modelArch=$model_arch" \
    --data-urlencode "deviceId=$device_id" \
    --data-urlencode "channel=$channel" >"$response"
fi

# The Store endpoint currently returns the whole applicable set even when
# search/limit are supplied. Emit JSON Lines so callers can filter locally
# without putting the full response into model context.
if command -v jq >/dev/null 2>&1; then
  jq -e '.result.apps | type == "array"' "$response" >/dev/null
  jq -c '.result.apps[]' "$response"
elif command -v jsonfilter >/dev/null 2>&1; then
  first="$(jsonfilter -q -i "$response" -e '@.result.apps[0].name' 2>/dev/null || :)"
  [ -n "$first" ] || { echo 'invalid or empty iStore catalog response' >&2; exit 1; }
  jsonfilter -q -i "$response" -e '@.result.apps[*]'
else
  echo 'jq or jsonfilter is required to parse the iStore catalog' >&2
  exit 1
fi
