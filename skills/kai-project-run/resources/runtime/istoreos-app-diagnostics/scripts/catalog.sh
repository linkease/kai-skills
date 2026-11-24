#!/bin/sh
set -eu

app="${1:-}"
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
catalog="${ISTORE_DIAG_CATALOG_FILE:-$script_dir/../data/first-party-apps.jsonl}"
case "$app" in [A-Za-z0-9][A-Za-z0-9._+-]*) ;; *) printf 'catalog_match\tfalse\n'; exit 0 ;; esac

line=
if [ -f "$catalog" ]; then line="$(grep -m 1 "^{\"id\":\"$app\"[,}]" "$catalog" || :)"; fi
if [ -z "$line" ]; then
  printf 'catalog_match\tfalse\ncatalog_scope\tfirst_party\napp_type\tunknown\ncapabilities\t\n'
  exit 0
fi

app_type="$(printf '%s\n' "$line" | sed -n 's/.*"type":"\([^"]*\)".*/\1/p')"
capabilities=
for capability in autoconf istorec init config luci; do
  if printf '%s\n' "$line" | grep -F "\"$capability\":true" >/dev/null 2>&1; then
    if [ -n "$capabilities" ]; then capabilities="$capabilities,$capability"; else capabilities="$capability"; fi
  fi
done
printf 'catalog_match\ttrue\n'
printf 'catalog_scope\tfirst_party\n'
printf 'app_type\t%s\n' "$app_type"
printf 'capabilities\t%s\n' "$capabilities"
