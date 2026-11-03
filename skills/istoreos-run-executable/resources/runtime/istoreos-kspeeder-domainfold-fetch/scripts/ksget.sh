#!/bin/sh
set -eu

# Compatibility wrapper for the legacy skill entry.
# The download policy now lives in the KSpeeder binary.

usage() {
  cat >&2 <<'EOF'
Usage:
  ksget.sh URL
  ksget.sh -o FILE URL
  ksget.sh -O FILE URL
  ksget.sh -O URL

Environment:
  KSGET_MODE=auto|direct|accelerated|race|probe
  KSGET_JSON=1
  KSGET_EVENTS=ndjson
EOF
}

basename_from_url() {
  u="${1%%\?*}"
  u="${u%%#*}"
  b="${u##*/}"
  [ -n "$b" ] || b="download.bin"
  printf '%s\n' "$b"
}

if command -v iStoreEnhance >/dev/null 2>&1; then
  kspeeder_bin="iStoreEnhance"
elif command -v kspeeder >/dev/null 2>&1; then
  kspeeder_bin="kspeeder"
else
  echo "ksget.sh: iStoreEnhance/kspeeder binary not found; install or upgrade iStoreEnhance/KSpeeder first." >&2
  exit 127
fi

mode="${KSGET_MODE:-auto}"
json="${KSGET_JSON:-0}"
events="${KSGET_EVENTS:-}"
out=""
url=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -o)
      [ "$#" -ge 3 ] || { usage; exit 2; }
      out="$2"
      shift 2
      ;;
    -O)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      if [ "$#" -eq 2 ]; then
        url="$2"
        out="$(basename_from_url "$url")"
        shift 2
      else
        out="$2"
        shift 2
      fi
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "ksget.sh: unsupported legacy option: $1" >&2
      exit 2
      ;;
    *)
      [ -z "$url" ] || { usage; exit 2; }
      url="$1"
      shift
      ;;
  esac
done

if [ "$#" -gt 0 ]; then
  [ -z "$url" ] || { usage; exit 2; }
  url="$1"
  shift
fi

[ -n "$url" ] || { usage; exit 2; }

set -- download --mode "$mode"
if [ "$json" = "1" ]; then
  set -- "$@" --json
  [ -n "$events" ] || events="ndjson"
fi
if [ -n "$events" ]; then
  set -- "$@" --events "$events"
fi
if [ -n "$out" ]; then
  set -- "$@" -O "$out"
fi
exec "$kspeeder_bin" "$@" "$url"
