#!/bin/sh
# POSIX JSON construction only; no authorization or task routing.
kai_json_string() {
  if ! command -v awk >/dev/null 2>&1; then
    kai_json_rest=$1
    printf '"'
    while [ -n "$kai_json_rest" ]; do
      kai_json_tail=${kai_json_rest#?}
      kai_json_character=${kai_json_rest%"$kai_json_tail"}
      kai_json_rest=$kai_json_tail
      case "$kai_json_character" in
        '"') printf '\\"' ;;
        '\') printf '\\\\' ;;
        *)
          kai_json_ordinal=$(printf '%d' "'$kai_json_character")
          if [ "$kai_json_ordinal" -lt 32 ]; then printf '\\u%04x' "$kai_json_ordinal"
          else printf '%s' "$kai_json_character"; fi
          ;;
      esac
    done
    printf '"'
    return
  fi
  printf '%s_' "$1" | LC_ALL=C awk '
    { text=text (NR>1 ? "\n" : "") $0 }
    END {
      text=substr(text,1,length(text)-1); printf "\""
      for(i=1;i<=length(text);i++) {
        c=substr(text,i,1)
        if(c=="\\") printf "\\\\"
        else if(c=="\"") printf "\\\""
        else {
          control=0
          for(j=1;j<32;j++) if(c==sprintf("%c",j)) {printf "\\u%04x",j;control=1;break}
          if(!control) printf "%s",c
        }
      }
      printf "\""
    }'
}

kai_fact() {
  kai_fact_name=$1 kai_fact_json=$2 kai_fact_source=$3 kai_fact_status=$4
  [ -z "$kai_facts" ] || kai_facts="$kai_facts,"
  kai_facts="$kai_facts$(kai_json_string "$kai_fact_name"):$kai_fact_json"
  kai_evidence_index=$((kai_evidence_index+1))
  [ -z "$kai_evidence" ] || kai_evidence="$kai_evidence,"
  kai_evidence="$kai_evidence{\"id\":\"fact-$kai_evidence_index\",\"source\":$(kai_json_string "$kai_fact_source"),\"status\":$(kai_json_string "$kai_fact_status"),\"observedAt\":$(kai_json_string "$kai_observed"),\"factPaths\":[$(kai_json_string "/facts/$kai_fact_name")]}"
}

kai_error() {
  [ -z "$kai_errors" ] || kai_errors="$kai_errors,"
  kai_errors="$kai_errors{\"code\":$(kai_json_string "$1"),\"message\":$(kai_json_string "$2")}"
  [ "$kai_status" = failed ] || kai_status=partial
}

kai_emit_observation() { kai_emit_result true; }
# Serialization only. The caller records effects; this function performs no
# operation and never grants permissions. Observations always force empty effects.
kai_emit_operation() { kai_emit_result false; }
kai_emit_result() {
  kai_emit_read_only=$1
  kai_emit_effects='{"requested":[],"completed":[],"unknown":[],"remaining":[]}'
  kai_emit_verification='{"status":"not_required","checks":[]}'
  if [ "$kai_emit_read_only" = false ]; then
    kai_emit_effects="{\"requested\":$kai_effects_requested,\"completed\":$kai_effects_completed,\"unknown\":$kai_effects_unknown,\"remaining\":$kai_effects_remaining}"
    kai_emit_verification=$kai_verification
  fi
  kai_receipt="{\"schemaVersion\":1,\"operation\":$(kai_json_string "${kai_operation:-system.inspect}"),\"operationStatus\":$(kai_json_string "$kai_status"),\"targetId\":$(kai_json_string "$kai_target"),\"readOnly\":$kai_emit_read_only,\"observedAt\":$(kai_json_string "$kai_observed"),\"facts\":{$kai_facts},\"evidence\":[$kai_evidence],\"effects\":$kai_emit_effects,\"verification\":$kai_emit_verification,\"errors\":[$kai_errors],\"truncated\":false}"
  kai_receipt_bytes=$(printf '%s' "$kai_receipt" | wc -c | tr -d ' ')
  if [ "$kai_receipt_bytes" -gt 8192 ]; then
    kai_facts= kai_evidence= kai_evidence_index=0 kai_errors= kai_status=failed
    kai_error RESULT_LIMIT 'Selected facts exceed the default byte limit; query fewer sections.'
    kai_emit_result "$kai_emit_read_only"
    return 2
  fi
  printf '%s\n' "$kai_receipt"
  [ "$kai_status" = succeeded ]
}
