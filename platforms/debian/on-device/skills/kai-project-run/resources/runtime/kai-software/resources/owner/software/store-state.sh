# Read the selected app's installed record and registered dependencies only.
task_store_state() {
    local root=${ZSETUP_TASK_SYSTEM_ROOT:-} path meta installed= release= packages='[]'
    local package any_installed=false missing=false
    path="$root/tmp/run/istore-meta/meta/$TASK_SOFTWARE.json"
    # Older integrations expose the installed app records under this directory.
    if [ ! -f "$path" ]; then path="$root/usr/lib/opkg/meta/$TASK_SOFTWARE.json"; fi
    if [ -f "$path" ] && [ ! -L "$path" ]; then
        [ "$(wc -c < "$path")" -le 65536 ] || task_stop needs-ai invalid-installed-store-metadata 0
        meta=$("$task_jq" -c --arg name "$TASK_SOFTWARE" 'select(.name==$name)|{version,release}' "$path") || task_stop needs-ai invalid-installed-store-metadata 0
        "$task_jq" -e '(.version|type=="string" and test("^[A-Za-z0-9][A-Za-z0-9._+:~+-]{0,127}$")) and (.release|tostring|test("^[0-9]{1,9}$"))' <<< "$meta" >/dev/null || task_stop needs-ai invalid-installed-store-metadata 0
        installed=$("$task_jq" -r .version <<< "$meta"); release=$("$task_jq" -r '.release|tostring' <<< "$meta")
    fi
    while IFS= read -r package; do
        task_native_query "$package"
        [ "$("$task_jq" -r '.sourceConflict//false' <<< "$TASK_NATIVE")" != true ] || task_stop needs-ai native-source-conflict 0 "$TASK_NATIVE"
        if [ -n "$("$task_jq" -r .installedVersion <<< "$TASK_NATIVE")" ]; then any_installed=true; else missing=true; fi
        packages=$("$task_jq" -cn --argjson rows "$packages" --arg name "$package" --argjson fact "$TASK_NATIVE" '$rows+[$fact+{name:$name,functionalValidation:"not-run"}]')
    done < <("$task_jq" -r '.depends[]' <<< "$TASK_STORE_APP")
    TASK_STORE_STATE=$("$task_jq" -cn --arg installed "$installed" --arg release "$release" --argjson packages "$packages" --argjson any "$any_installed" --argjson missing "$missing" '{installedVersion:$installed,installedRelease:$release,packages:$packages,anyRegisteredPackage:$any,missingPackage:$missing}')
}
