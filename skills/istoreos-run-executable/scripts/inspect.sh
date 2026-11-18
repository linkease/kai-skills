#!/bin/sh
set -eu

file="${1:-}"

have() { command -v "$1" >/dev/null 2>&1; }

need() {
  echo "need: $*" >&2
  exit 2
}

human_mib() {
  bytes="${1:-0}"
  awk -v b="$bytes" 'BEGIN { printf "%.2f MiB", (b/1024/1024) }' 2>/dev/null || echo "${bytes}B"
}

if [ -z "$file" ]; then
  echo "usage: $0 <FILE.run>" >&2
  exit 2
fi

if [ ! -f "$file" ]; then
  need "file not found: $file"
fi

echo "## path"
ls -la "$file" 2>/dev/null || true

echo ""
echo "## size"
bytes=""
if have stat; then
  bytes="$(stat -c %s "$file" 2>/dev/null || true)"
fi
if [ -z "${bytes:-}" ] && have wc; then
  bytes="$(wc -c <"$file" 2>/dev/null | tr -d ' ' || true)"
fi
if [ -n "${bytes:-}" ]; then
  echo "bytes=$bytes"
  echo "mib=$(human_mib "$bytes")"
  if [ "$bytes" -ge 209715200 ] 2>/dev/null; then
    echo "risk_hint=very_large_file (>=200MiB; likely heavy writes/extraction; inspect write scope before execution)"
  elif [ "$bytes" -ge 52428800 ] 2>/dev/null; then
    echo "risk_hint=large_file (>=50MiB; inspect write scope before execution)"
  fi
else
  echo "bytes=unknown"
fi

echo ""
echo "## type"
if have file; then
  file "$file" 2>/dev/null || true
else
  echo "file=missing"
fi

echo ""
echo "## signature"
sig="$(dd if="$file" bs=2 count=1 2>/dev/null || true)"
if [ "$sig" = "#!" ]; then
  echo "shebang=yes (likely script/self-extracting installer)"
else
  elf="$(dd if="$file" bs=4 count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n' || true)"
  if [ "$elf" = "7f454c46" ]; then
    echo "elf=yes"
  else
    echo "elf=no/unknown"
  fi
fi

echo ""
echo "## checksum"
if have sha256sum; then
  sha256sum "$file" 2>/dev/null || true
else
  echo "sha256sum=missing"
fi

echo ""
echo "## platform"
uname -a 2>/dev/null || true
uname -m 2>/dev/null || true

echo ""
echo "## disk"
df -hP / 2>/dev/null || true
df -hP "$(dirname "$file")" 2>/dev/null || true

echo ""
echo "## next"
echo "1) Treat .run as risky and identify whether it writes system config, external data, firmware, partitions, or databases."
echo "2) KAIPlus protects covered system writes with a Linkspace recovery point; active protection must be reused, not duplicated."
echo "3) Direct shell use and out-of-scope data have no automatic protection. After reviewing scope, run only with explicit CONFIRM_RUN_EXEC=YES."
