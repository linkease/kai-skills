# Business entry: choose a channel once, then report facts and missing evidence.
task_inspect() {
    local installed candidate decision source
    . "$task_root/platform.sh"; task_platform
    . "$task_root/native-compare.sh"
    if [ "$TASK_STORE" = true ]; then
        . "$task_root/store-catalog.sh"; . "$task_root/store-inspect.sh"
        task_store_inspect && return 0
    fi
    task_native_query
    [ "$("$task_jq" -r '.sourceConflict//false' <<< "$TASK_NATIVE")" != true ] || task_stop needs-ai native-source-conflict 0 "$TASK_NATIVE"
    installed=$("$task_jq" -r .installedVersion <<< "$TASK_NATIVE")
    candidate=$("$task_jq" -r .candidateVersion <<< "$TASK_NATIVE")
    task_native_compare "$("$task_jq" -r .manager <<< "$TASK_NATIVE")" "$installed" "$candidate"
    if [ -z "$installed" ]; then decision=not-installed
    elif [ -z "$candidate" ]; then decision=candidate-unknown
    else
        case "$TASK_COMPARISON" in same) decision=no-update-in-cache ;; candidate-newer) decision=update-available-in-cache ;; installed-newer) decision=installed-newer ;; *) decision=comparison-unknown ;; esac
    fi
    source=$("$task_jq" -c '.source//{id:.manager,freshness:"cache-unverified",fetchedAt:null}' <<< "$TASK_NATIVE")
    TASK_INSPECTED=$("$task_jq" -c --arg decision "$decision" --arg comparison "$TASK_COMPARISON" --argjson source "$source" '.+{decision:$decision,comparison:$comparison,source:$source,functionalValidation:"not-run"}' <<< "$TASK_NATIVE")
    task_result success inspected 0 "$TASK_INSPECTED"
}
