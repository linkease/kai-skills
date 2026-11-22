# Store application identity and native package identity remain separate.
task_store_inspect() {
    local root=${ZSETUP_TASK_SYSTEM_ROOT:-} meta path installed= release= candidate candidate_release
    local packages='[]' package any_installed=false missing=false decision
    [ "$TASK_STORE_CATALOG_FOR" = "$TASK_SOFTWARE" ] || task_store_catalog
    [ "$TASK_STORE_APP" != null ] || return 1
    "$task_jq" -e '(.name|type=="string") and (.version|type=="string" and test("^[A-Za-z0-9][A-Za-z0-9._+:~+-]{0,127}$")) and (.release|tostring|test("^[0-9]{1,9}$")) and (.depends|type=="array" and length<=64 and all(.[];type=="string" and test("^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$")))' <<< "$TASK_STORE_APP" >/dev/null || task_stop failed invalid-store-application 11
    candidate=$("$task_jq" -r .version <<< "$TASK_STORE_APP")
    candidate_release=$("$task_jq" -r '.release|tostring' <<< "$TASK_STORE_APP")
    . "$task_root/store-state.sh"; task_store_state
    installed=$("$task_jq" -r .installedVersion <<< "$TASK_STORE_STATE")
    release=$("$task_jq" -r .installedRelease <<< "$TASK_STORE_STATE")
    packages=$("$task_jq" -c .packages <<< "$TASK_STORE_STATE")
    any_installed=$("$task_jq" -r .anyRegisteredPackage <<< "$TASK_STORE_STATE")
    missing=$("$task_jq" -r .missingPackage <<< "$TASK_STORE_STATE")
    TASK_INSPECTED=$("$task_jq" -cn --arg installed "$installed" --arg candidate "$candidate" --arg release "$release" --arg candidateRelease "$candidate_release" --argjson source "$TASK_STORE_SOURCE" --argjson packages "$packages" --argjson app "$TASK_STORE_APP" \
        '{manager:"istore",installedVersion:$installed,installedRelease:$release,candidateVersion:$candidate,candidateRelease:$candidateRelease,compatibility:$app.compatibility,source:$source,packages:$packages,functionalValidation:"not-run"}')
    [ "$("$task_jq" -r .compatibility <<< "$TASK_STORE_APP")" = supported ] || task_stop needs-ai store-platform-compatibility-unconfirmed 0 "$TASK_INSPECTED"
    if [ -z "$installed" ]; then
        [ "$any_installed" != true ] || task_stop needs-ai store-ownership-unconfirmed 0 "$TASK_INSPECTED"
        decision=not-installed
    else
        [ "$missing" != true ] || task_stop needs-ai store-dependency-not-installed 0 "$TASK_INSPECTED"
        task_native_compare "$TASK_MANAGER" "$installed-r$release" "$candidate-r$candidate_release"
        case "$TASK_COMPARISON" in
            same) decision=no-update ;;
            candidate-newer) decision=update-available ;;
            installed-newer) decision=installed-newer ;;
            *) task_stop needs-ai native-version-comparison-required 0 "$TASK_INSPECTED" ;;
        esac
    fi
    TASK_INSPECTED=$("$task_jq" -c --arg decision "$decision" '.+{decision:$decision}' <<< "$TASK_INSPECTED")
    [ "${1:-emit}" != emit ] || task_result success inspected 0 "$TASK_INSPECTED"
    return 0
}
