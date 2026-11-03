#!/bin/sh
set -eu

requested="${1:-latest}"
detail_phase=
if [ "${2:-}" = --detail ]; then detail_phase="${3:-all}"; fi
case "$detail_phase" in ''|all|package|autoconf|runtime) ;; *) echo "invalid detail phase" >&2; exit 2 ;; esac

script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

if [ -n "$detail_phase" ]; then "$script_dir/collect.sh" "$requested" --detail >"$tmp/collected";
else "$script_dir/collect.sh" "$requested" >"$tmp/collected"; fi
"$script_dir/state.sh" "$tmp/collected" >"$tmp/state"
"$script_dir/classify.sh" "$tmp/collected" "$tmp/state" >"$tmp/classified"

field() { awk -F '\t' -v key="$2" '$1 == key { sub(/^[^\t]*\t/, ""); print; exit }' "$1"; }
quote() {
  awk 'BEGIN { ORS=""; print "\"" }
    { if (NR > 1) print "\\n"; gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); print }
    END { print "\"" }'
}
json_string() { printf '%s' "$1" | quote; }
json_nullable_string() { if [ -n "$1" ]; then json_string "$1"; else printf null; fi; }
json_nullable_int() { case "$1" in ''|*[!0-9-]*) printf null ;; *) printf '%s' "$1" ;; esac; }
json_nullable_bool() { case "$1" in true|false) printf '%s' "$1" ;; *) printf null ;; esac; }

app="$(field "$tmp/collected" requested_app)"
"$script_dir/catalog.sh" "${app:-unknown}" >"$tmp/catalog"
"$script_dir/store-app.sh" "${app:-unknown}" >"$tmp/store"
task_app="$(field "$tmp/collected" task_app)"
task_package=
[ -n "$task_app" ] && task_package="app-meta-$task_app"
correlation="$(field "$tmp/collected" correlation)"
log_available="$(field "$tmp/collected" log_available)"
historical=false
if [ "$correlation" = exact ] && [ "$log_available" = true ]; then historical=true; fi
next_skill="$(field "$tmp/classified" next_skill)"
next_detail="$detail_phase"

printf '{'
printf '"schema_version":1,'
printf '"requested_app":'; json_string "${app:-unknown}"; printf ','
printf '"task":{'
printf '"id":"istore","state":'; json_string "$(field "$tmp/collected" state)"; printf ','
printf '"correlation":'; json_string "$correlation"; printf ','
printf '"exit_code":'; json_nullable_int "$(field "$tmp/collected" exit_code)"; printf ','
printf '"action":'; json_nullable_string "$(field "$tmp/collected" action)"; printf ','
printf '"package":'; json_nullable_string "$task_package"; printf ','
printf '"enable_requested":'; json_nullable_int "$(field "$tmp/collected" enable_requested)"; printf ','
printf '"target_path":'; json_nullable_string "$(field "$tmp/collected" target_path)"; printf ','
printf '"started_at":'; json_nullable_int "$(field "$tmp/collected" start)"; printf ','
printf '"stopped_at":'; json_nullable_int "$(field "$tmp/collected" stop)"; printf ','
printf '"age_seconds":'; json_nullable_int "$(field "$tmp/collected" age_seconds)"; printf '},'
printf '"result":{'
printf '"outcome":'; json_string "$(field "$tmp/classified" outcome)"; printf ','
printf '"primary_code":'; json_string "$(field "$tmp/classified" primary_code)"; printf ','
printf '"summary":'; json_string "$(field "$tmp/classified" summary)"; printf ','
printf '"confidence":'; json_string "$(field "$tmp/classified" confidence)"; printf '},'
printf '"device":{'
printf '"package_installed":'; json_nullable_bool "$(field "$tmp/state" package_installed)"; printf ','
printf '"meta_present":%s,' "$(field "$tmp/state" meta_present)"
printf '"autoconf_present":%s,' "$(field "$tmp/state" autoconf_present)"
printf '"istorec_present":%s,' "$(field "$tmp/state" istorec_present)"
printf '"init_script_present":%s,' "$(field "$tmp/state" init_script_present)"
printf '"config_present":%s,' "$(field "$tmp/state" config_present)"
printf '"service_state":'; json_nullable_string "$(field "$tmp/state" service_state)"; printf ','
printf '"container_state":'; json_nullable_string "$(field "$tmp/state" container_state)"; printf '},'
printf '"evidence":['
printf '{"source":"task","code":'; json_string "$(field "$tmp/classified" primary_code)"; printf ',"message":'; json_string "$(field "$tmp/classified" summary)"; printf '}'
if [ "$(field "$tmp/state" package_installed)" != null ]; then
  printf ',{"source":"package","code":"PACKAGE_STATE","message":'; json_string "package_installed=$(field "$tmp/state" package_installed)"; printf '}'
fi
if [ "$(field "$tmp/catalog" catalog_match)" = true ]; then
  printf ',{"source":"catalog","code":"FIRST_PARTY_SOURCE_HINT","message":'; json_string "scope=first_party type=$(field "$tmp/catalog" app_type) capabilities=$(field "$tmp/catalog" capabilities)"; printf '}'
fi
if [ "$(field "$tmp/store" store_match)" = true ]; then
  printf ',{"source":"catalog","code":"STORE_CATALOG_MATCH","message":'; json_string "scope=all title=$(field "$tmp/store" title) type=$(field "$tmp/store" app_type) autoconf=$(field "$tmp/store" autoconf) arch=$(field "$tmp/store" arch)"; printf '}'
fi
printf '],'
printf '"next":{"skill":'; json_nullable_string "$next_skill"; printf ',"detail":'; json_nullable_string "$next_detail"; printf '},'
printf '"limits":{"historical_log_available":%s,"log_truncated":%s,"untrusted_log":true}' "$historical" "$(field "$tmp/collected" log_truncated)"
if [ -n "$detail_phase" ]; then
  sed -n '/^--LOG--$/,$p' "$tmp/collected" | sed '1d' | "$script_dir/detail-log.sh" "$detail_phase" >"$tmp/detail-log"
  if [ "$(field "$tmp/classified" outcome)" = unknown ]; then
    "$script_dir/system-log.sh" "${app:-unknown}" >>"$tmp/detail-log"
  fi
  printf ',"detail":{"phase":'; json_string "$detail_phase"; printf ',"log_excerpt":'; quote <"$tmp/detail-log"; printf '}'
fi
printf '}\n'
