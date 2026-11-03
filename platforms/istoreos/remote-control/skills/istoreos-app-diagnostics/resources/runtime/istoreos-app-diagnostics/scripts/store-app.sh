#!/bin/sh
set -eu

app="${1:-}"
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
fetch="$script_dir/../../istoreos-app-search/scripts/fetch-store.sh"
case "$app" in [A-Za-z0-9][A-Za-z0-9._+-]*) ;; *) printf 'store_match\tfalse\n'; exit 0 ;; esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
if [ ! -x "$fetch" ] || ! "$fetch" >"$tmp/apps.jsonl" 2>/dev/null; then
  printf 'store_match\tfalse\n'
  exit 0
fi

object=
if command -v jq >/dev/null 2>&1; then
  object="$(jq -c --arg app "$app" 'select(.name == $app)' "$tmp/apps.jsonl" | head -n 1)"
else
  while IFS= read -r candidate; do
    name="$(jsonfilter -q -s "$candidate" -e '@.name' 2>/dev/null || :)"
    if [ "$name" = "$app" ]; then object="$candidate"; break; fi
  done <"$tmp/apps.jsonl"
fi

if [ -z "$object" ]; then
  printf 'store_match\tfalse\n'
  exit 0
fi

json_value() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$object" | jq -r "$1" 2>/dev/null || :
  else
    jsonfilter -q -s "$object" -e "$2" 2>/dev/null || :
  fi
}
title="$(json_value '.title // .title_en // ""' '@.title' | tr '\n\t' '  ')"
depends="$(json_value '(.depends // []) | join(" ")' '@.depends[*]' | tr '\n\t' '  ')"
arch="$(json_value '(.arch // []) | join(",")' '@.arch[*]' | tr '\n\t ' ',,,')"
autoconf=false
if command -v jq >/dev/null 2>&1; then
  if printf '%s\n' "$object" | jq -e '.autoconf != null' >/dev/null 2>&1; then autoconf=true; fi
else
  autoconf_type="$(jsonfilter -q -s "$object" -t '@.autoconf' 2>/dev/null || :)"
  case "$autoconf_type" in object|array|string|number|boolean) autoconf=true ;; esac
fi
app_type=native
if printf '%s\n' "$depends" | grep -Eiq 'docker-deps|(^|[[:space:]])docker([[:space:]]|$)'; then app_type=docker; fi

printf 'store_match\ttrue\n'
printf 'title\t%s\n' "$title"
printf 'app_type\t%s\n' "$app_type"
printf 'autoconf\t%s\n' "$autoconf"
printf 'arch\t%s\n' "$arch"
