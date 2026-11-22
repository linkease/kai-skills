# Execute the platform's existing app lifecycle, then verify local facts.
task_store_apply() {
    local expected=$1 arg code=0 details action=upgrade
    local argv=()
    TASK_EFFECTS='["native-package-operation-attempt","native-package-hooks"]'
    [ "$("$task_jq" -r '.observed.decision' <<< "$expected")" != not-installed ] || action=install
    if [ "$action" = upgrade ]; then
        while IFS= read -r -d '' arg; do argv+=("$arg"); done < <("$task_jq" -j '.catalog.depends[]|.+"\u0000"' <<< "$expected")
    fi
    argv+=("app-meta-$TASK_SOFTWARE")
    printf '%s\n' 'Applying the reviewed application through iStore.' >&2
    is-opkg "$action" "${argv[@]}" >"$TASK_STORE_TMP/operation.log" 2>&1 || code=$?
    [ "$code" = 0 ] || task_stop failed store-operation-failed "$code" '{"verificationRequired":true}'
    TASK_STORE_APP=$("$task_jq" -c .catalog <<< "$expected")
    . "$task_root/store-state.sh";task_store_state
    [ "$("$task_jq" -r .installedVersion <<< "$TASK_STORE_STATE")" = "$("$task_jq" -r .version <<< "$expected")" ] && \
        [ "$("$task_jq" -r .installedRelease <<< "$TASK_STORE_STATE")" = "$("$task_jq" -r '.catalog.release|tostring' <<< "$expected")" ] && \
        [ "$("$task_jq" -r .missingPackage <<< "$TASK_STORE_STATE")" = false ] || task_stop failed store-verification-failed 11 "$TASK_STORE_STATE"
    details=$("$task_jq" -c --argjson source "$TASK_STORE_SOURCE" '.+{source:$source,verification:"store-record-and-native-registration",functionalValidation:"not-run"}' <<< "$TASK_STORE_STATE")
    task_result success updated 0 "$details" "$TASK_EFFECTS"
}
