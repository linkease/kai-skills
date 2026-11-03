#!/bin/sh
# System package boundary: queries never refresh repositories implicitly.
set -eu
action="${1:-detect}"
subject="${2:-}"
system_root="${ISTORE_SYSTEM_ROOT:-}"
fail() { printf '%s\n' "failed: $*" >&2; exit 4; }
have() { command -v "$1" >/dev/null 2>&1; }
case "$system_root" in ''|/*) ;; *) fail 'system root must be absolute' ;; esac
if [ ! -f "$system_root/etc/openwrt_release" ] && ! grep -Eiq '^(ID|ID_LIKE)=.*(openwrt|istoreos)' "$system_root/etc/os-release" 2>/dev/null; then
  fail 'unsupported-system: use the target distribution package skill (Ubuntu is not iStoreOS)'
fi
opkg_db=0
apk_db=0
[ ! -f "$system_root/usr/lib/opkg/status" ] || opkg_db=1
for db in "$system_root/lib/apk/db/installed" "$system_root/usr/lib/apk/db/installed"; do
  [ ! -f "$db" ] || apk_db=1
done
[ "$opkg_db:$apk_db" != 1:1 ] || fail 'ambiguous package databases: inspect the active system integration before choosing'
case "$opkg_db:$apk_db" in
  1:0) have opkg || fail 'opkg database exists but executable is missing'; manager=opkg ;;
  0:1) have apk || fail 'apk database exists but executable is missing'; manager=apk ;;
  *) fail 'no active opkg/apk database; inspect system image and package integration' ;;
esac
installer="$manager"
if [ "$manager" = opkg ] && have is-opkg; then installer=is-opkg; fi
valid_package() {
  case "$subject" in ''|-*|*[!A-Za-z0-9._+-]*) fail 'invalid package name' ;; esac
}
available() {
  if [ "$manager" = opkg ]; then
    candidates="$(opkg list "$subject")" || fail 'feed query failed; inspect sources and explicitly refresh if authorized'
    printf '%s\n' "$candidates" | awk -v package="$subject" '$1 == package && $2 == "-" { found=1 } END { exit !found }' || fail "package-unavailable: $subject is not in the cached configured feeds"
  else
    candidates="$(apk search -x "$subject")" || fail 'feed query failed; inspect repositories and explicitly refresh if authorized'
    case "$candidates" in "$subject"-[0-9]*|"$subject") ;; *) fail "package-unavailable: $subject is not in the cached configured feeds" ;; esac
  fi
}
case "$action" in
  detect)
    printf 'package_manager=%s\npackage_installer=%s\n' "$manager" "$installer"
    printf 'package_executable=%s\n' "$(command -v "$manager")"
    ;;
  search)
    [ -n "$subject" ] || fail 'a search term is required'
    case "$subject" in -*) fail 'invalid search term' ;; esac
    if [ "$manager" = opkg ]; then
      result="$(opkg list)" || fail 'feed query failed'
      printf '%s\n' "$result" | grep -iF -- "$subject" | head -n 30
    else
      apk search -v "$subject"
    fi
    ;;
  owner)
    case "$subject" in /*) ;; *) fail 'an absolute file path is required' ;; esac
    if [ "$manager" = opkg ]; then exec opkg search "$subject"; else exec apk info --who-owns "$subject"; fi
    ;;
  info|installed|files|available)
    valid_package
    case "$action:$manager" in
      available:*) available; printf '%s\n' "$candidates" ;;
      info:opkg) opkg info "$subject" ;;
      info:apk) apk info -a "$subject" ;;
      installed:opkg)
        state="$(opkg status "$subject")" || fail "package-not-installed: $subject"
        printf '%s\n' "$state" | grep -Eq '^Status:.*[[:space:]]installed$' || fail "package-not-installed: $subject"
        printf '%s\n' "$state"
        ;;
      installed:apk) apk info -e "$subject" ;;
      files:opkg) opkg files "$subject" ;;
      files:apk) apk info -L "$subject" ;;
    esac
    ;;
  refresh|install|upgrade|remove)
    [ "${KAIPLUS_CONFIRMED:-}" = 1 ] || fail 'need-confirmation: package/index changes require authorization'
    if [ "$action" = refresh ]; then exec "$manager" update; fi
    valid_package
    if [ "$action" != remove ]; then available; fi
    case "$action:$manager" in
      install:opkg) exec "$installer" install "$subject" ;;
      upgrade:opkg) exec "$installer" upgrade "$subject" ;;
      remove:opkg) exec "$installer" remove "$subject" ;;
      install:apk) exec apk add "$subject" ;;
      upgrade:apk) exec apk upgrade "$subject" ;;
      remove:apk) exec apk del "$subject" ;;
    esac
    ;;
  *) fail 'usage: package.sh detect|search|info|available|installed|files|refresh|install|upgrade|remove [subject]' ;;
esac
