#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)"
pack="$root/components/system-packs/istoreos"

fail() {
  echo "failed: $*" >&2
  exit 1
}

routing_bytes="$(wc -c <"$pack/TASK_ROUTING.md" | tr -d ' ')"
[ "$routing_bytes" -le 2048 ] || fail "routing injection is $routing_bytes bytes; budget is 2048"

catalog="$(${AWK:-awk} '
  FNR == 1 { manual=0; name=""; description="" }
  /^invocation:[[:space:]]*manual/ { manual=1 }
  /^name:/ { sub(/^name:[[:space:]]*/, ""); name=$0 }
  /^description:/ { sub(/^description:[[:space:]]*/, ""); description=$0 }
  /^---$/ && FNR > 1 {
    if (!manual && name != "") print name " — " description
    nextfile
  }
' "$pack"/skills/*/SKILL.md "$root/components/system-packs/common"/skills/*/SKILL.md)"
catalog_bytes="$(printf '%s' "$catalog" | wc -c | tr -d ' ')"
[ "$catalog_bytes" -le 3072 ] || fail "catalog is $catalog_bytes bytes; budget is 3072"

prompt_bytes="$(( $(wc -c <"$pack/agents/system.md") + $(wc -c <"$pack/agents/istoreos.md") ))"
[ "$prompt_bytes" -le 2048 ] || fail "always-on prompts are $prompt_bytes bytes; budget is 2048"

sh "$pack/tests/test_app_diagnostics_release.sh"
sh "$pack/tests/test_unknown_observer.sh"
sh "$pack/tests/test_skill_architecture.sh"

printf 'M7 context budgets: PASS (catalog=%s routing=%s prompt=%s)\n' \
  "$catalog_bytes" "$routing_bytes" "$prompt_bytes"
