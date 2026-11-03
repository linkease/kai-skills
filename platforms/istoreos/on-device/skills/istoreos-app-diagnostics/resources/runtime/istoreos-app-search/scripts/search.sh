#!/bin/sh
set -eu

query="${1:-}"
top="${2:-3}"
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
skill_dir="$(dirname "$script_dir")"
skills_dir="$(dirname "$skill_dir")"
aliases="${ISTORE_APP_ALIASES:-$skill_dir/data/intent-aliases.tsv}"
first_party="${ISTORE_FIRST_PARTY_INDEX:-$(CDPATH= cd -- "$(dirname "$0")/../../../.." && pwd -P)/data/first-party-apps.jsonl}"

[ -n "$query" ] || { echo 'usage: search.sh <keyword> [top]' >&2; exit 2; }
case "$top" in ''|*[!0-9]*|0) echo 'top must be a positive integer' >&2; exit 2 ;; esac
[ "$top" -le 20 ] || top=20

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
catalog_source=istore-store-api
[ -z "${ISTORE_STORE_RESPONSE_FILE:-}" ] || catalog_source=store-fixture

# Store is authoritative. When unavailable, the bundled first-party manifest is
# a deliberately incomplete but deterministic fallback; never label it as the
# complete Store inventory.
if ! "$script_dir/fetch-store.sh" >"$tmp/apps.jsonl" 2>"$tmp/store.err"; then
  [ -r "$first_party" ] || { cat "$tmp/store.err" >&2; exit 1; }
  : >"$tmp/apps.jsonl"
  while IFS= read -r object; do
    id="$(printf '%s\n' "$object" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
    type="$(printf '%s\n' "$object" | sed -n 's/.*"type":"\([^"]*\)".*/\1/p')"
    [ -n "$id" ] || continue
    printf '{"name":"%s","title":"%s","description":"","tags":["%s"],"depends":[],"entry":""}\n' "$id" "$id" "$type" >>"$tmp/apps.jsonl"
  done <"$first_party"
  catalog_source=first-party-offline
fi

json_value() {
  object="$1"; jq_expr="$2"; filter_expr="$3"
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$object" | jq -r "$jq_expr" 2>/dev/null || :
  else
    jsonfilter -q -s "$object" -e "$filter_expr" 2>/dev/null || :
  fi
}

contains() { printf '%s\n' "$1" | grep -Fi -- "$2" >/dev/null 2>&1; }

alias_terms=
preferred_names=
if [ -r "$aliases" ]; then
  tab="$(printf '\t')"
  while IFS="$tab" read -r phrase terms preferred; do
    case "$phrase" in ''|'#'*) continue ;; esac
    if contains "$query" "$phrase"; then
      alias_terms="$alias_terms $terms"
      preferred_names="$preferred_names $preferred"
    fi
  done <"$aliases"
fi

add_reason() {
  current="$1"; reason="$2"
  case ",$current," in
    *",$reason,"*) printf '%s' "$current" ;;
    *) printf '%s' "${current:+$current,}$reason" ;;
  esac
}

: >"$tmp/scored.tsv"
while IFS= read -r object; do
  [ -n "$object" ] || continue
  name="$(json_value "$object" '.name // ""' '@.name')"
  title="$(json_value "$object" '.title // .title_en // ""' '@.title')"
  description="$(json_value "$object" '(.description // .description_en // "") | gsub("[\\r\\n\\t]"; " ")' '@.description')"
  tags="$(json_value "$object" '(.tags // []) | join(" ")' '@.tags[*]' | tr '\n\t' '  ')"
  depends="$(json_value "$object" '(.depends // []) | join(" ")' '@.depends[*]' | tr '\n\t' '  ')"
  entry="$(json_value "$object" '.entry // ""' '@.entry')"
  [ -n "$name" ] || continue

  score=0; reasons=
  if contains "$name" "$query"; then score=$((score + 100)); reasons="$(add_reason "$reasons" name)"; fi
  if contains "$title" "$query"; then score=$((score + 60)); reasons="$(add_reason "$reasons" title)"; fi
  if contains "$tags" "$query"; then score=$((score + 30)); reasons="$(add_reason "$reasons" category)"; fi
  if contains "$description" "$query"; then score=$((score + 10)); reasons="$(add_reason "$reasons" feature)"; fi

  for term in $alias_terms; do
    if contains "$name $title $tags $description" "$term"; then
      score=$((score + 12))
      reasons="$(add_reason "$reasons" intent)"
    fi
  done
  case " $preferred_names " in
    *" $name "*)
      score=$((score + 50))
      reasons="$(add_reason "$reasons" intent)"
      ;;
  esac

  [ "$score" -gt 0 ] || continue
  type_hint=native
  if printf '%s\n' "$depends $tags" | grep -Eiq 'docker-deps|(^|[[:space:]])docker([[:space:]]|$)'; then type_hint=docker; fi
  ownership=community
  if [ -r "$first_party" ] && grep -F -- "\"id\":\"$name\"" "$first_party" >/dev/null 2>&1; then ownership=first-party; fi
  compatibility=store-filtered
  [ "$catalog_source" != first-party-offline ] || compatibility=unknown-offline
  title="$(printf '%s' "$title" | tr '\n\t' '  ')"
  entry="$(printf '%s' "$entry" | tr '\n\t' '  ')"
  [ -n "$entry" ] || entry=-
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$score" "$name" "$title" "$type_hint" "$entry" "$reasons" "$ownership" "$compatibility" "$catalog_source" >>"$tmp/scored.tsv"
done <"$tmp/apps.jsonl"

quote() {
  awk 'BEGIN { ORS=""; print "\"" } { if (NR > 1) print "\\n"; gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); print } END { print "\"" }'
}
json_string() { printf '%s' "$1" | quote; }
fit_label() {
  case "$1" in
    name) printf '名称匹配' ;;
    title) printf '标题匹配' ;;
    category) printf '分类匹配' ;;
    feature) printf '功能匹配' ;;
    intent) printf '使用意图匹配' ;;
    *) printf '%s' "$1" ;;
  esac
}

printf '['
count=0
tab="$(printf '\t')"
sort -t "$tab" -k1,1nr -k2,2 "$tmp/scored.tsv" | head -n "$top" |
while IFS="$tab" read -r score name title type_hint entry reasons ownership compatibility source; do
  [ "$count" -eq 0 ] || printf ','
  count=$((count + 1))
  printf '{"name":'; json_string "$name"
  printf ',"title":'; json_string "$title"
  printf ',"type_hint":'; json_string "$type_hint"
  printf ',"entry":'; json_string "$entry"
  printf ',"ownership":'; json_string "$ownership"
  printf ',"compatibility":'; json_string "$compatibility"
  printf ',"catalog_source":'; json_string "$source"
  printf ',"fit":['
  first=true
  old_ifs="$IFS"; IFS=','
  for reason in $reasons; do
    [ "$first" = true ] || printf ','
    first=false
    json_string "$(fit_label "$reason")"
  done
  IFS="$old_ifs"
  printf ']}'
done
printf ']\n'
