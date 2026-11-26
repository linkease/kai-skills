#!/bin/sh
set -eu
pack=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
observe="$pack/skills/istoreos-system-task-router/scripts/observe.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
if sh "$observe" unknown >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
if sh "$observe" service ../shadow >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
jq -e '.operationStatus=="failed" and .errors[0].code=="INVALID_ARGUMENT"' "$tmp/out" >/dev/null
sh "$observe" auto >"$tmp/auto"
jq -e '.operation=="system.inspect" and .readOnly==true and .targetId=="local" and (.observedAt|length>0) and (.facts.os.distribution|length>0) and .effects.requested==[]' "$tmp/auto" >/dev/null
[ "$(wc -c < "$tmp/auto")" -le 8192 ]
printf '%s\n' 'ok: explicit observation returns a bounded read-only receipt'
