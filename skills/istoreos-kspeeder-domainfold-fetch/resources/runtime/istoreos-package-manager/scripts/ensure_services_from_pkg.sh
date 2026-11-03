#!/bin/sh
set -eu

pkg="${1:-}"
if [ -z "$pkg" ]; then
  echo "usage: $0 <opkg_package_name>" >&2
  exit 2
fi

have() { command -v "$1" >/dev/null 2>&1; }
need() {
  echo "need-confirmation: $*" >&2
  exit 2
}

skills_root() {
  dir="$(dirname "$0")"
  skill="$(dirname "$dir")"
  dirname "$skill"
}

ensure() {
  svc="$1"
  cfg="${2:-}"
  root="$(skills_root)"
  script="$root/istoreos-service-manager/scripts/ensure.sh"
  if [ ! -f "$script" ]; then
    need "missing dependency skill script: $script"
  fi
  sh "$script" "$svc" "$cfg"
}

here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
files="$(sh "$here/package.sh" files "$pkg")"
if [ -z "$files" ]; then
  need "cannot list files for $pkg; confirm package name or whether it is installed"
fi

files="$(printf '%s\n' "$files" | sed 's#^etc/#/etc/#')"
svcs="$(printf '%s\n' "$files" | sed -n 's#^/etc/init.d/##p' | awk 'NF{print $1}' | sort -u)"

if [ -z "$svcs" ]; then
  echo "ok: no init.d services found in opkg files for $pkg" >&2
  exit 0
fi

printf '%s\n' "$svcs" | while IFS= read -r svc; do
  [ -n "$svc" ] || continue
  cfg="$svc"
  if printf '%s\n' "$files" | grep -q "^/etc/config/$cfg$" 2>/dev/null; then
    ensure "$svc" "$cfg"
  else
    ensure "$svc"
  fi
done

echo "ok: ensured services from pkg=$pkg" >&2
