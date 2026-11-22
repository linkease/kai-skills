task_owner_digest() {
    local file
    for file in "$task_root"/*.sh "$task_root"/*.ps1 "$task_root/releases.lock.json" \
        "$task_root/../apps/jq/0.1.0/installer.sh" \
        "$task_root/../apps/jq/source/artifacts.lock.json"; do
        [ -f "$file" ] && [ ! -L "$file" ] || return 2
        task_digest "$file" || return $?
    done | task_hash_input
}
task_version_matches() {
    local wanted=$1 actual=$2 wanted_epoch actual_epoch
    [ -n "$actual" ] || return 1
    [ -z "$wanted" ] && return 0
    [ "$wanted" = "$actual" ] && return 0
    if [[ "$wanted" == *:* ]];then
        wanted_epoch=${wanted%%:*};actual_epoch=${actual%%:*}
        [ "$wanted_epoch" = "$actual_epoch" ] || return 1
        wanted=${wanted#*:}
    fi
    [[ "$actual" != *:* ]] || actual=${actual#*:}
    # Native packaging revisions may extend an exact upstream release. Alpha,
    # beta, rc and tilde upstream prereleases are not that stable release.
    case "$actual" in
        "$wanted"|"$wanted"-[0-9]*|"$wanted"-r[0-9]*|"$wanted"+dfsg*|"$wanted"+ds[0-9]*|"$wanted"+deb[0-9]*|"$wanted".el[0-9]*) return 0 ;;
        *) return 1 ;;
    esac
}
task_owner_artifact() {
    local raw key value artifact= digest= size= url= version= code
    raw=$(ZSETUP_INSTALLER_MODE=1 sh "$task_root/../apps/jq/0.1.0/installer.sh" --plan); code=$?
    [ "$code" = 0 ] || task_stop blocked owner-plan-failed "$code"
    while IFS='=' read -r key value; do
        case "$key" in artifact) artifact=$value ;; sha256) digest=$value ;; size) size=$value ;; url) url=$value ;; version) version=$value ;; esac
    done <<< "$raw"
    [ -n "$artifact" ] && [ -n "$digest" ] && [ -n "$size" ] && [ -n "$url" ] || task_stop failed invalid-owner-plan 11
    TASK_ARTIFACT=$("$task_jq" -cn --arg name "$artifact" --arg sha "$digest" --arg url "$url" --arg version "$version" --argjson size "$size" '{name:$name,sha256:$sha,url:$url,size:$size,version:$version}')
}
