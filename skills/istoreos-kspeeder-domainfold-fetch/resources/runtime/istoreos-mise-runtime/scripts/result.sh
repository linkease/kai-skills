#!/bin/sh
# POSIX shell + awk only: routers do not need jq or a system Python for receipts.
result_string() {
  printf '"'
  printf '%s' "$1" | awk '
    BEGIN {
      for (i=1;i<32;i++) escape[sprintf("%c",i)]=sprintf("\\u%04x",i)
      escape["\""]="\\\""; escape["\\"]="\\\\"
    }
    { if (NR>1) printf "\\n"; for (i=1;i<=length($0);i++) {
        c=substr($0,i,1); printf "%s", (c in escape ? escape[c] : c)
      }
    }'
  printf '"'
}
result_emit() {
  result_status="$1"; result_operation="$2"; result_code="$3"; shift 3
  printf '{"schemaVersion":1,"status":'
  result_string "$result_status"
  printf ',"operation":'; result_string "$result_operation"
  printf ',"exitCode":%s' "$result_code"
  while [ "$#" -gt 0 ]; do
    printf ','; result_string "$1"; printf ':'; result_string "$2"; shift 2
  done
  printf '}\n'
}
