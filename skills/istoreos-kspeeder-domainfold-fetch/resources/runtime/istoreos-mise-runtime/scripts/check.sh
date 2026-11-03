#!/bin/sh
set -eu
runtime="${1:-all}"
case "$runtime" in python|node|go|all) ;; *) echo 'usage: check.sh python|node|go|all' >&2; exit 2 ;; esac
system_root="${ISTORE_SYSTEM_ROOT:-}"
if [ ! -f "$system_root/etc/openwrt_release" ] && ! grep -Eiq '^(ID|ID_LIKE)=.*(openwrt|istoreos)' "$system_root/etc/os-release" 2>/dev/null; then
  echo 'failed: unsupported-system: use the Ubuntu/Linux runtime workflow' >&2
  exit 4
fi
printf '[system]\n'
printf 'scope=system-current-shell\n'
for release in "$system_root/etc/openwrt_release" "$system_root/etc/os-release"; do
  [ ! -r "$release" ] || grep -E '^(DISTRIB_(ID|RELEASE|ARCH|TARGET)|ID|VERSION_ID|ID_LIKE)=' "$release" || true
done
printf 'architecture=%s\n' "$(uname -m)"
libc=unknown
for loader in "$system_root"/lib/ld-musl-*.so*; do [ ! -e "$loader" ] || libc=musl; done
if [ "$libc" = unknown ] && command -v getconf >/dev/null 2>&1 && getconf GNU_LIBC_VERSION >/dev/null 2>&1; then libc=glibc; fi
printf 'libc=%s\n' "$libc"
[ ! -r "$system_root/proc/cpuinfo" ] || grep -Ei '^(flags|features)[[:space:]]*:' "$system_root/proc/cpuinfo" | head -n 2 || true
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
sh "$here/../../istoreos-package-manager/scripts/package.sh" detect || true
for tool in mise-exec mise mise-istore ks-cli uci pip python node go realpath gcc cc; do
  if command -v "$tool" >/dev/null 2>&1; then printf 'tool.%s=%s\n' "$tool" "$(command -v "$tool")"; else printf 'tool.%s=missing\n' "$tool"; fi
done
runtime_dir=""
if command -v uci >/dev/null 2>&1; then runtime_dir="$(uci -q get mise.main.runtime_dir 2>/dev/null || true)"; fi
printf 'runtime_dir=%s\n' "${runtime_dir:-not-configured}"
if [ -n "$runtime_dir" ] && [ -d "$runtime_dir" ]; then
  df -P -k "$runtime_dir" 2>/dev/null || true
  mount 2>/dev/null | grep -E ' on /overlay | on / ' || true
fi
if [ -n "$runtime_dir" ] && [ "${HOME:-}" = "$runtime_dir" ]; then
  case "$PATH" in "$HOME/.local/share/mise/shims:"*) environment=integrated ;; *) environment=missing-shims ;; esac
else environment=enter-mise-exec; fi
printf 'environment=%s\n' "$environment"
for var in XDG_DATA_HOME XDG_CACHE_HOME XDG_CONFIG_HOME MISE_DATA_DIR MISE_CACHE_DIR MISE_CONFIG_DIR; do
  # These fixed names need no external printenv binary or dynamic eval.
  case "$var" in
    XDG_DATA_HOME) value=${XDG_DATA_HOME:-} ;;
    XDG_CACHE_HOME) value=${XDG_CACHE_HOME:-} ;;
    XDG_CONFIG_HOME) value=${XDG_CONFIG_HOME:-} ;;
    MISE_DATA_DIR) value=${MISE_DATA_DIR:-} ;;
    MISE_CACHE_DIR) value=${MISE_CACHE_DIR:-} ;;
    MISE_CONFIG_DIR) value=${MISE_CONFIG_DIR:-} ;;
  esac
  printf '%s=%s\n' "$var" "${value:-unset}"
done
if [ -n "${XDG_DATA_HOME:-}" ] && [ -z "${MISE_DATA_DIR:-}" ]; then
  echo 'diagnosis=agent-xdg-runtime-conflict: use exec.sh or updated integrated mise; HOME alone does not select mise data storage'
fi
if command -v mise >/dev/null 2>&1; then
  mise --version
  # Avoid reading a different HOME's installed versions or creating integration directories.
  if [ "$environment" = integrated ]; then
    if [ "$runtime" = all ]; then mise ls python node go; else mise ls "$runtime"; fi
  fi
fi
