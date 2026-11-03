#!/bin/sh
set -eu

# fetch: download a URL to a local file (prefer KSpeeder DomainFold ksget if available).
#
# Usage:
#   fetch.sh -o <out_file> <URL>
#   fetch.sh <URL>                  # save to /tmp/istoreos-run-executable/<basename>
#
# Stdout: prints the saved file path only (for scripts to capture).

usage() {
  echo "usage: $0 [-o <out_file>] <URL>" >&2
}

out_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o)
      shift
      [ $# -gt 0 ] || { usage; exit 2; }
      out_file="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "unsupported option: $1" >&2
      usage
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

url="${1:-}"
[ -n "$url" ] || { usage; exit 2; }

tmp_dir="${RUN_TMP_DIR:-/tmp/istoreos-run-executable}"
mkdir -p "$tmp_dir" 2>/dev/null || true

basename_from_url() {
  # strip query/fragment, then take last path segment
  u="$1"
  b="$(printf '%s' "$u" | sed 's/[?#].*$//' | awk -F/ '{print $NF}')"
  if [ -z "$b" ] || [ "$b" = "/" ]; then
    echo "download.run"
  else
    echo "$b"
  fi
}

if [ -z "$out_file" ]; then
  out_file="$tmp_dir/$(basename_from_url "$url")"
fi

part="${out_file}.syn.$$"

resolve_skills_dir() {
  if [ -n "${KAIPLUS_SKILLS_DIR:-}" ] && [ -d "$KAIPLUS_SKILLS_DIR" ]; then
    printf '%s\n' "$KAIPLUS_SKILLS_DIR"
    return 0
  fi
  if [ -n "${KAIPLUS_HOME:-}" ] && [ -d "$KAIPLUS_HOME/config/skills" ]; then
    printf '%s\n' "$KAIPLUS_HOME/config/skills"
    return 0
  fi
  script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P || true)"
  if [ -n "$script_dir" ]; then
    script_skill_dir="$(dirname "$(dirname "$script_dir")")"
    skills_dir="$(dirname "$script_skill_dir")"
    if [ -d "$skills_dir" ]; then
      printf '%s\n' "$skills_dir"
      return 0
    fi
  fi
  return 1
}

SKILLS_DIR="$(resolve_skills_dir || true)"

ksget=""
if [ -n "${SKILLS_DIR:-}" ] && [ -f "$(CDPATH= cd -- "$(dirname "$0")/../resources/runtime/istoreos-kspeeder-domainfold-fetch" && pwd -P)/scripts/ksget.sh" ]; then
  ksget="$(CDPATH= cd -- "$(dirname "$0")/../resources/runtime/istoreos-kspeeder-domainfold-fetch" && pwd -P)/scripts/ksget.sh"
fi

download_ok=0
if command -v iStoreEnhance >/dev/null 2>&1; then
  if iStoreEnhance download --mode auto --json --events ndjson -O "$part" "$url" >/dev/null 2>&1; then
    download_ok=1
  fi
elif command -v kspeeder >/dev/null 2>&1; then
  if kspeeder download --mode auto --json --events ndjson -O "$part" "$url" >/dev/null 2>&1; then
    download_ok=1
  fi
fi

if [ "$download_ok" -ne 1 ] && [ -n "$ksget" ]; then
  if sh "$ksget" -o "$part" "$url" >/dev/null 2>&1; then
    download_ok=1
  fi
fi

if [ "$download_ok" -ne 1 ]; then
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 10 -o "$part" "$url" >/dev/null
    download_ok=1
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$part" "$url" >/dev/null 2>&1
    download_ok=1
  elif command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -O "$part" "$url" >/dev/null 2>&1
    download_ok=1
  else
    echo "need: curl/wget/uclient-fetch not found" >&2
    exit 2
  fi
fi

if [ ! -s "$part" ]; then
  rm -f "$part" 2>/dev/null || true
  echo "download failed or empty: $url" >&2
  exit 1
fi

cat "$part" >"$out_file" 2>/dev/null || mv -f "$part" "$out_file"
rm -f "$part" 2>/dev/null || true

printf '%s\n' "$out_file"
