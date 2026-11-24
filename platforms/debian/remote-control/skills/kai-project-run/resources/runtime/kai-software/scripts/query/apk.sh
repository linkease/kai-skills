# Cached package names only; version/source comparison stays with the owner.
query_apk() {
 command -v apk >/dev/null 2>&1 || fail missing-apk
 apk --no-network search -q --description -- "$query" >"$work/names" 2>"$work/private.log" || fail provider-query-failed
 if [ ! -s "$work/names" ];then status=needs-ai;reason=cache-candidate-unknown;fi
 jq -Rn --arg query "$query" '[inputs|select(test("^[A-Za-z0-9][A-Za-z0-9._+-]*$"))|{id:("apk:"+.),name:.,source:"apk",kind:"package",evidence:{freshness:"native-cache-unverified",runtimeVersion:"unknown"}}]' <"$work/names"
}
