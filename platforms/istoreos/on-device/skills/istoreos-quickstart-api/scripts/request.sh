#!/bin/sh
set -eu

method="${1:-}"
path="${2:-}"
body="${3:-}"
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || {
  echo "usage: request.sh METHOD PATH [JSON_BODY]" >&2
  exit 2
}

case "$method" in GET|HEAD) ;; POST|PUT|PATCH|DELETE) ;; *) echo "failed: unsupported method" >&2; exit 2 ;; esac
case "$path" in /*) ;; *) echo "failed: endpoint path must start with /" >&2; exit 2 ;; esac
case "$path" in *..*) echo "failed: endpoint traversal is not allowed" >&2; exit 2 ;; esac

case "$path" in
  /system/reboot/*|/system/poweroff/*|/system/setPassword/*|/network/*|/wireless/*|/nas/disk/*|/raid/*|/app/install/*|/share/*)
    [ "$method" = "GET" ] || [ "${QUICKSTART_DANGER_APPROVED:-}" = "YES" ] || {
      echo "failed: dangerous QuickStart change requires QUICKSTART_DANGER_APPROVED=YES" >&2
      exit 3
    }
    ;;
esac

skills_dir="${SKILLS_DIR:-}"
if [ -z "$skills_dir" ]; then
  here="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
  skills_dir="$(dirname "$here")"
fi
controller="$(CDPATH= cd -- "$(dirname "$0")/../resources/runtime/luci-http-controller" && pwd -P)/scripts/lucihttp.go"
[ -f "$controller" ] || { echo "failed: luci-http-controller is not installed" >&2; exit 2; }
[ -n "${TARGET_HTTP_HOST:-}" ] || { echo "failed: TARGET_HTTP_HOST is required" >&2; exit 2; }
[ -n "${TARGET_LUCI_USER:-}" ] || { echo "failed: TARGET_LUCI_USER is required" >&2; exit 2; }
[ -n "${TARGET_LUCI_PASSWORD:-}" ] || { echo "failed: TARGET_LUCI_PASSWORD is required" >&2; exit 2; }

set -- go run "$controller" --host "$TARGET_HTTP_HOST" --user "$TARGET_LUCI_USER" \
  --password-env TARGET_LUCI_PASSWORD --prefix /cgi-bin/luci/istore "$method" "$path"
[ -z "$body" ] || set -- "$@" "$body"
response="$("$@")"
printf '%s\n' "$response"
if command -v jq >/dev/null 2>&1; then
  success="$(printf '%s' "$response" | jq -er '.success // 0')" || exit 1
  [ "$success" -eq 0 ] || { echo "failed: QuickStart success=$success" >&2; exit 1; }
fi
