#!/usr/bin/env bash
set -eu
set -o pipefail
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/../../kai-tool-bootstrap/scripts/jq-env.sh"
if ! kai_use_jq full 2>/dev/null;then
 printf '%s\n' '{"protocol":"software-query/v1","schemaVersion":1,"status":"blocked","reason":"complete-jq-required","items":[],"effects":[]}'
 exit 21
fi
fail() { jq -cn --arg reason "$1" '{protocol:"software-query/v1",schemaVersion:1,status:"blocked",reason:$reason,items:[],effects:[]}';exit "${2:-21}"; }
action=${1:-}; request=${2:-}
case "$action" in search|detail|inspect) ;; *) fail unsupported-query-action 2 ;; esac
[ -f "$request" ] && [ ! -L "$request" ] || fail invalid-request 2
[ "$(wc -c < "$request")" -le 8192 ] || fail request-too-large 2
jq -e 'type=="object" and ((keys-["targetId","query","id","software","provider","limit"])|length==0) and (.targetId|type=="string") and ([.query,.id,.software,.provider]|all(.==null or (type=="string" and length<=256))) and ((if .limit==null then 3 else .limit end)|type=="number" and floor==. and .>=1 and .<=10)' "$request" >/dev/null || fail invalid-request 2
target=$(jq -r .targetId "$request"); [ "$target" = "${ZSETUP_TASK_TARGET_ID:-local}" ] || fail target-mismatch 2
limit=$(jq -r '.limit//3' "$request"); query=$(jq -r '.query//.id//.software//""' "$request")
[ -n "$query" ] && [ "${query#-}" = "$query" ] || fail query-required 2
platform=${KAI_PLATFORM:-$(bash "$here/../../kai-tool-bootstrap/scripts/tool.sh" probe bash | jq -er .platform)}
provider=$(jq -r '.provider//""' "$request")
if [ -z "$provider" ];then
 case "$query" in *:*) provider=${query%%:*} ;; *) case "$platform" in ubuntu|debian) provider=apt ;; macos) provider=brew ;; istoreos|openwrt) if command -v is-opkg >/dev/null 2>&1;then provider=istore;elif command -v opkg >/dev/null 2>&1;then provider=opkg;else provider=apk;fi ;; linux) if command -v apt-cache >/dev/null 2>&1;then provider=apt;elif command -v opkg >/dev/null 2>&1;then provider=opkg;elif command -v apk >/dev/null 2>&1;then provider=apk;else fail provider-required;fi ;; *) fail provider-required ;; esac ;; esac
fi
case "$provider" in docker-image|docker-container) provider=docker ;; esac
case "$provider:$platform" in apt:ubuntu|apt:debian|apt:linux|opkg:linux|opkg:openwrt|opkg:istoreos|apk:openwrt|apk:istoreos|apk:linux|istore:istoreos|istore:openwrt|brew:macos|brew-cask:macos|zsetup:ubuntu|zsetup:debian|zsetup:linux|zsetup:istoreos|zsetup:openwrt|docker:*) ;; *) fail unsupported-provider ;; esac
if [ "$action" = detail ];then case "$query" in *:*) ;; *) fail source-qualified-id-required 2 ;; esac;fi
work=$(umask 077;mktemp -d);trap 'rm -rf "$work"' EXIT
status=success;reason=;code=0;native=null
if [ "$provider" = docker ];then
 . "$here/query/docker.sh"; query_docker >"$work/rows.json"
elif [ "$provider" = brew ] || [ "$provider" = brew-cask ];then
 . "$here/query/brew.sh"; query_brew >"$work/rows.json"
elif [ "$action" = search ] && [ "$provider" = istore ];then
 entry="$here/../../istoreos-app-search/scripts/search.sh"
 [ -f "$entry" ] || entry="$here/../resources/runtime/istoreos-app-search/scripts/search.sh"
 [ -f "$entry" ] || fail istore-search-unavailable
 sh "$entry" "$query" "$((limit+1))" >"$work/source.json" 2>"$work/private.log" || fail provider-query-failed
 jq '[.[]|{id:("istore:"+.name),name,title,kind:.type_hint,source:.catalog_source,compatibility,matchReason:(.fit|join(","))}]' "$work/source.json" >"$work/rows.json"
elif [ "$provider" = apk ] && [ "$action" = search ];then
 . "$here/query/apk.sh"; query_apk >"$work/rows.json"
elif [ "$action" != search ] && { [ "$action" = inspect ] && [ "$provider" != zsetup ] || [ "$provider" = istore ] || [ "$provider" = apk ] || [ "$provider" = opkg ]; };then
 software=$(jq -r '.software//.id' "$request");software=${software#*:}
 jq --arg software "$software" '{targetId,software:$software}' "$request" >"$work/inspect.json"
 sh "$here/task-entry.sh" inspect "$work/inspect.json" >"$work/source.json" 2>"$work/private.log" || code=$?
 jq -e '.protocol=="software-task/v1" and (.details|type=="object")' "$work/source.json" >/dev/null || fail invalid-provider-result
 native=$(jq -r '(.nativeExitCode//null)' "$work/source.json");status=$(jq -r .status "$work/source.json");reason=$(jq -r .reason "$work/source.json")
 jq --arg provider "$provider" --arg software "$software" '[.details|.+{id:($provider+":"+(.canonicalSoftwareId//$software)),name:(.canonicalSoftwareId//$software),source:(.manager//$provider),evidence:{source:(.source|{id,freshness,fetchedAt}),missingEvidence:((.missingEvidence//[])[:10]),packagesTruncated:((.packages//[]|length)>10)}}]' "$work/source.json" >"$work/rows.json"
else
 subject=$query;[ "$action" = search ] || { case "$query" in "$provider":*) ;; *) fail source-qualified-id-required 2 ;; esac; }
 op=info;[ "$action" != search ] || op=search
 KAI_SOFTWARE_SEARCH_LIMIT=$((limit+1)) KAI_SOFTWARE_PROVIDER=$provider bash "$here/software.sh" "$op" "$subject" >"$work/source.json" 2>"$work/private.log" || fail provider-query-failed
 jq 'if type=="array" then . else [.] end' "$work/source.json" >"$work/rows.json"
fi
jq -ce 'type=="array" and all(.[];(.id|type=="string" and length>0 and length<=256))' "$work/rows.json" >/dev/null || fail invalid-provider-result
jq -c --arg action "$action" --arg target "$target" --arg query "$query" --arg status "$status" --arg reason "$reason" --argjson native "$native" --argjson limit "$limit" -f "$here/query/result.jq" "$work/rows.json" >"$work/result.json"
[ "$(wc -c < "$work/result.json")" -le 8192 ] || fail query-result-too-large 20
cat "$work/result.json"
exit "$code"
