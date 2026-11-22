# Homebrew supplies its own outdated decision; no generic version ordering.
task_query_brew() {
    local raw code=0
    raw=$(HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 brew info --json=v2 --formula "$native_name" 2>/dev/null) || code=$?
    [ "$code" = 0 ] || task_stop failed provider-query-failed "$code"
    "$task_jq" -e '.formulae|type=="array" and length==1' <<< "$raw" >/dev/null || task_stop failed invalid-brew-result 11
    candidate=$("$task_jq" -r '.formulae[0].versions.stable//""' <<< "$raw")
    installed=$("$task_jq" -r '.formulae[0].installed[0].version//""' <<< "$raw")
    native_extra=$("$task_jq" -c '.formulae[0]|{updateAvailable:(.outdated//null),pinned:(.pinned//false)}' <<< "$raw")
}
