#!/usr/bin/env bash
# Small composition layer: existing owners prepare jq and native zsetup.
set -u
here="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
action="${1:-probe}"
case "$action" in probe|plan|ensure) ;; *) exit 2 ;; esac
. "$here/jq-env.sh"
code=0
jq_receipt="$(bash "$here/jq.sh" "$action")" || code=$?
if [ "$code" != 0 ] || ! kai_use_jq full 2>/dev/null; then
    [ -n "$jq_receipt" ] || jq_receipt='{"status":"failed","reason":"empty-jq-receipt"}'
    printf '{"schemaVersion":1,"protocol":"kai-runtime/v1","ready":false,"status":"preparation-required","stage":"jq","tools":{"jq":%s},"exitCode":%s}\n' "$jq_receipt" "$code"
    exit "$code"
fi
core_receipt="$(bash "$here/tool.sh" "$action" zsetup)" || code=$?
if ! printf '%s' "$core_receipt" | jq -e 'type=="object" and (.status|type=="string")' >/dev/null 2>&1; then
    core_receipt='{"status":"failed","reason":"invalid-core-receipt"}'; code=11
fi
ready=false
if [ "$code" = 0 ] && [ "$(printf '%s' "$core_receipt" | jq -r .status)" = reused ]; then ready=true; fi
# Existing ensure can report installed; accept only the verified owner result.
if [ "$code" = 0 ] && [ "$(printf '%s' "$core_receipt" | jq -r .status)" = installed ]; then ready=true; fi
jq -cn --argjson ready "$ready" --argjson jq "$jq_receipt" --argjson core "$core_receipt" \
    --arg bash "$BASH" --arg version "$BASH_VERSION" --argjson code "$code" \
    '{schemaVersion:1,protocol:"kai-runtime/v1",ready:$ready,status:(if $ready then "ready" else "preparation-required" end),stage:"zsetup",tools:{bash:{path:$bash,version:$version,status:"reused"},jq:$jq,zsetup:$core},exitCode:$code}'
exit "$code"
