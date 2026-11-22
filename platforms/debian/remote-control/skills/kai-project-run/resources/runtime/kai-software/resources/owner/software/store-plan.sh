# iStore remains the installation owner. Plans bind channel, versions and state.
task_store_plan() {
    local input intent version observation catalog storage=null backup=null combined=null saved effects='[]' current=false
    input=${1:-$(task_request_digest)}; intent=$("$task_jq" -r '.intent//"install"' <<< "$TASK_REQUEST_JSON")
    . "$task_root/platform.sh"; task_platform
    [ "$TASK_STORE:$TASK_MANAGER" = true:opkg ] || task_stop needs-ai verified-store-write-adapter-required 0
    task_store_inspect observe || task_stop needs-ai store-application-not-found 0
    observation=$("$task_jq" -c 'del(.source.fetchedAt)' <<< "$TASK_INSPECTED")
    catalog=$TASK_STORE_APP
    version=$("$task_jq" -r .candidateVersion <<< "$observation")
    case "$intent" in install|update) ;; *) task_stop needs-ai store-removal-owner-required 0 "$observation" ;; esac
    case "$("$task_jq" -r .decision <<< "$observation")" in
        not-installed) [ "$intent" != update ] || task_stop needs-ai store-application-not-installed 0 "$observation" ;;
        no-update|installed-newer) current=true ;;
    esac
    [ -z "$("$task_jq" -r '.version//""' <<< "$TASK_REQUEST_JSON")" ] || \
        [ "$("$task_jq" -r .version <<< "$TASK_REQUEST_JSON")" = "$version" ] || task_stop needs-ai no-compatible-store-candidate 0 "$observation"
    if [ "$current" != true ]; then
        "$task_jq" -e 'has("storage")' <<< "$TASK_REQUEST_JSON" >/dev/null || task_stop needs-ai native-package-storage-budget-required 0 "$observation"
        task_storage_plan;storage=$TASK_STORAGE_PLAN
        effects='["native-index-refresh","native-package-operation","native-package-hooks"]'
        if [ "$("$task_jq" -r '.backupRequired//false' <<< "$TASK_REQUEST_JSON")" = true ]; then
            task_backup_plan;backup=$TASK_BACKUP_PLAN;saved=$TASK_REQUEST_JSON
            task_backup_add_budget;task_storage_plan;combined=$TASK_STORAGE_PLAN;TASK_REQUEST_JSON=$saved
        fi
    fi
    TASK_PLAN=$("$task_jq" -cn --arg input "$input" --arg request "$(task_request_digest)" --arg owner "$(task_owner_digest)" \
        --arg intent "$intent" --arg version "$version" --argjson current "$current" --argjson observation "$observation" --argjson catalog "$catalog" \
        --argjson storage "$storage" --argjson backup "$backup" --argjson combined "$combined" --argjson effects "$effects" \
        '{method:"istore",intent:$intent,version:$version,alreadyCurrent:$current,observed:$observation,catalog:$catalog,inputDigest:$input,requestDigest:$request,ownerDigest:$owner,storagePlan:$storage,backupPlan:$backup,combinedStoragePlan:$combined,effects:$effects,rollbackPolicy:"native-package-hooks-not-atomic; use selected host protection"}')
    TASK_PLAN=$("$task_jq" -c --arg digest "$("$task_jq" -cS . <<< "$TASK_PLAN" | task_hash_input)" '.+{planDigest:$digest}' <<< "$TASK_PLAN")
}
