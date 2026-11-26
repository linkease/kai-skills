#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
fixtures="$root/tests/fixtures/app-diagnostics"
collector="$root/skills/istoreos-app-diagnostics/scripts/collect.sh"
classifier="$root/skills/istoreos-app-diagnostics/scripts/classify.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

field() { awk -F '\t' -v key="$2" '$1 == key { print $2; exit }' "$1"; }

count=0
while IFS="$(printf '\t')" read -r case_name requested expected_outcome expected_code expected_correlation; do
  case "$case_name" in ''|'#'*) continue ;; esac
  ISTORE_DIAG_TASK_STATUS_FILE="$fixtures/$case_name/task-status.json" \
  ISTORE_DIAG_LOG_FILE="$fixtures/$case_name/istore.log" ISTORE_DIAG_NOW=1789173400 \
    "$collector" "$requested" >"$tmp/collected"
  "$classifier" "$tmp/collected" >"$tmp/classified"
  actual_outcome="$(field "$tmp/classified" outcome)"
  actual_code="$(field "$tmp/classified" primary_code)"
  actual_correlation="$(field "$tmp/collected" correlation)"
  [ "$actual_outcome" = "$expected_outcome" ] || {
    echo "failed: $case_name outcome=$actual_outcome expected=$expected_outcome" >&2; exit 1;
  }
  [ "$actual_code" = "$expected_code" ] || {
    echo "failed: $case_name code=$actual_code expected=$expected_code" >&2; exit 1;
  }
  [ "$actual_correlation" = "$expected_correlation" ] || {
    echo "failed: $case_name correlation=$actual_correlation expected=$expected_correlation" >&2; exit 1;
  }
  next_count="$(awk -F '\t' '$1 == "next_skill" && $2 != "" { count++ } END { print count + 0 }' "$tmp/classified")"
  [ "$next_count" -eq 0 ]
  count=$((count + 1))
done <"$fixtures/cases.tsv"

# Exit status has priority over misleading success text.
sed '/^--LOG--$/a Installation completed successfully' "$tmp/collected" >"$tmp/misleading"
"$classifier" "$tmp/misleading" >"$tmp/misleading-classified"
[ "$(field "$tmp/misleading-classified" outcome)" = autoconf_failed ] || {
  echo "failed: success text overrode the non-zero exit classification" >&2
  exit 1
}
printf 'ok: app diagnostics classifier passed %s contract cases\n' "$count"
