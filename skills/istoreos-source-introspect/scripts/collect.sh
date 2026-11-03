#!/bin/sh
set -eu

key="${1:-}"
root="${ISTOREOS_ROOT:-}"
root="${root%/}"

have() { command -v "$1" >/dev/null 2>&1; }

need() {
  echo "need: $*" >&2
  exit 2
}

redact() {
  # Apply the same redaction to UCI, source, diffs, and URLs. Device scripts
  # occasionally embed credentials, so source text is not inherently safe.
  sed -E \
    -e "s#((password|passwd|token|secret|apikey|api_key|access_key|private_key|psk|auth|authorization)[[:space:]]*=[[:space:]]*)('[^']*'|\"[^\"]*\"|[^[:space:]]+)#\\1'***'#gI" \
    -e "s#([?&](password|passwd|token|secret|apikey|api_key|access_key|private_key|psk|auth|authorization)=)[^&[:space:]]+#\\1***#gI" \
    -e 's#(://)[^/@[:space:]]+:[^/@[:space:]]+@#\1***:***@#g'
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

section() {
  echo ""
  echo "## $*"
}

if [ -z "$key" ]; then
  echo "usage: $0 <name-or-keyword>" >&2
  exit 2
fi
if ! valid_identifier "$key"; then
  echo "invalid identifier: use letters, digits, dot, underscore, plus, or hyphen; traversal is not allowed" >&2
  exit 2
fi

init="$root/etc/init.d/$key"
conf="$root/etc/config/$key"
rom_init="$root/rom/etc/init.d/$key"
rom_conf="$root/rom/etc/config/$key"
luci="$root/usr/lib/lua/luci"
rom_luci="$root/rom/usr/lib/lua/luci"

echo "target=$key"

section "platform"
uname -a 2>/dev/null || true

section "paths"
ls -la "$init" "$conf" 2>/dev/null || true
ls -la "$rom_init" "$rom_conf" 2>/dev/null || true

section "uci"
if have uci; then
  uci -q show "$key" 2>/dev/null | redact | head -n 220 || true
else
  echo "uci=missing"
fi

section "init-script (head)"
if [ -f "$init" ]; then
  sed -n '1,220p' "$init" 2>/dev/null | redact || true
else
  echo "missing=$init"
fi

section "init-script (rom head)"
if [ -f "$rom_init" ]; then
  sed -n '1,220p' "$rom_init" 2>/dev/null | redact || true
else
  echo "missing=$rom_init"
fi

section "init-script diff (rom vs overlay)"
if [ -f "$rom_init" ] && [ -f "$init" ]; then
  if have diff; then
    diff -u "$rom_init" "$init" 2>/dev/null | head -n 160 | redact || true
  else
    echo "diff=missing"
  fi
else
    echo "skip=need both $rom_init and $init"
fi

section "opkg"
if have opkg; then
  opkg status "app-meta-$key" 2>/dev/null | head -n 60 || true
  opkg status "$key" 2>/dev/null | head -n 60 || true
else
  echo "opkg=missing"
fi

section "luci (package files)"
if have opkg; then
  # best-effort: list luci files from packages whose name includes the key
  # (avoid expensive full filesystem scans on constrained devices)
  pkgs="$(opkg list-installed 2>/dev/null | awk '{print $1}' | grep -i -- "$key" | head -n 12 || true)"
  if [ -n "${pkgs:-}" ]; then
    echo "$pkgs" | while IFS= read -r p; do
      [ -n "$p" ] || continue
      echo "-- pkg=$p"
      opkg files "$p" 2>/dev/null | grep -E '^/usr/lib/lua/luci/' | head -n 120 || true
    done
  else
    echo "hint=no matching installed pkg names for keyword: $key"
  fi
else
  echo "skip=opkg missing"
fi

section "luci (filesystem match, small sample)"
if [ -d "$luci" ]; then
  find "$luci" -type f \( -name "*$key*" -o -path "*/$key/*" \) 2>/dev/null | head -n 60 || true
else
  echo "missing=$luci"
fi

section "luci (rom exists)"
if [ -d "$rom_luci" ]; then
  echo "rom_luci=present"
else
  echo "rom_luci=missing"
fi

section "next"
echo "1) If you need to change config or restart services, treat as risky: suggest full system backup first (istoreos-backup-restore)."
echo "2) If outputs include secrets, redact before sharing; only share minimal relevant sections."
