#!/bin/sh
# Preserve the old opkg query interface without implicit repository updates.
set -eu
action="${1:-}"
subject="${2:-}"
limit="${3:-30}"
[ -n "$subject" ] || { echo 'failed: a package or query pattern is required' >&2; exit 2; }
case "$subject" in -*) echo 'failed: query must not be an option' >&2; exit 2 ;; esac
case "$limit" in ''|*[!0-9]*) echo 'failed: limit must be an integer' >&2; exit 2 ;; esac
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
facts="$(sh "$here/package.sh" detect)"
if ! printf '%s\n' "$facts" | grep -qx 'package_manager=opkg'; then
  echo 'failed: legacy opkg regexp queries require opkg; use package.sh search/info/owner on apk' >&2
  exit 4
fi
find_candidates() {
  if opkg --help 2>/dev/null | grep -qE '^[[:space:]]*find[[:space:]]'; then
    result="$(opkg find "$subject")"
    if [ -n "$result" ]; then
      printf '%s\n' "$result" | head -n "$limit"
      return 0
    fi
  fi
  result="$(opkg list)"
  printf '%s\n' "$result" | grep -i -- "$subject" | head -n "$limit"
}
case "$action" in
  find) find_candidates ;;
  info)
    result="$(opkg info "$subject" 2>/dev/null || true)"
    if [ -n "$result" ]; then printf '%s\n' "$result"; exit 0; fi
    candidates="$(find_candidates | awk '{print $1}')"
    [ -n "$candidates" ] || { echo 'no-candidates' >&2; exit 1; }
    printf '%s\n' "$candidates" | while IFS= read -r package; do
      [ -z "$package" ] || opkg info "$package"
    done
    ;;
  owner)
    result="$(opkg search "$subject")"
    printf '%s\n' "$result" | head -n "$limit"
    ;;
  *) echo 'usage: legacy-query.sh find|info|owner QUERY [LIMIT]' >&2; exit 2 ;;
esac
