# Read-only native Formula/Cask queries; no refresh or bootstrap.
query_brew() {
 local kind=formula name raw names
 [ "$provider" != brew-cask ] || kind=cask
 command -v brew >/dev/null 2>&1 || fail missing-brew
 if [ "$action" = search ];then
  names=$(HOMEBREW_NO_AUTO_UPDATE=1 brew search --"$kind" -- "$query" 2>"$work/private.log") || fail provider-query-failed
  printf '%s\n' "$names" | awk -v exact="$query" 'NF && !seen[$0]++ {print ($0==exact?0:1),$0}' | sort -k1,1n -k2,2 | cut -d' ' -f2- | head -n "$((limit+1))" >"$work/names"
 else
  case "$query" in "$provider":*/*/*) name=${query#*:} ;; *) fail complete-brew-identity-required 2 ;; esac
  printf '%s\n' "$name" >"$work/names"
 fi
 : >"$work/brew.jsonl"
 while IFS= read -r name;do
  [ -n "$name" ] || continue
  case "$name" in *[!A-Za-z0-9._+/@-]*|-*) fail invalid-provider-identity ;; esac
  raw=$(HOMEBREW_NO_AUTO_UPDATE=1 brew info --json=v2 --"$kind" -- "$name" 2>"$work/private.log") || fail provider-query-failed
  printf '%s' "$raw" | jq -c --arg kind "$kind" 'def tap: .tap//(if $kind=="cask" then "homebrew/cask" else "homebrew/core" end); def qualified: if ((.full_name//"")|split("/")|length)==3 then .full_name else (tap+"/"+(.token//.name)) end; (if $kind=="cask" then .casks else .formulae end)[] | {id:((if $kind=="cask" then "brew-cask:" else "brew:" end)+qualified),name:(.name|if type=="array" then .[0] else . end),description:.desc,source:tap,kind:$kind,availableVersion:(.versions.stable//.version),installedVersion:(if (.installed|type)=="array" then .installed[0].version else .installed end),evidence:{runtimeVersion:"unknown",freshness:"native-cache"}}' >>"$work/brew.jsonl" || fail invalid-provider-result
 done <"$work/names"
 jq -s . "$work/brew.jsonl"
}
