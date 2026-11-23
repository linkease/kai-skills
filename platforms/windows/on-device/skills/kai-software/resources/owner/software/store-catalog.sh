# iStore metadata query. Product downloads stay with zsetup and app installers.
task_store_catalog() {
    local core=${KAI_ZSETUP_BIN:-${ZSETUP_BIN:-}} version api query root=${ZSETUP_TASK_SYSTEM_ROOT:-}
    local super_arch= model_arch= channel= device_id= code=0
    [ -n "$core" ] || core=$(type -P zsetup || true)
    [ -n "$core" ] || { [ ! -x "$HOME/.local/bin/zsetup" ] || core=$HOME/.local/bin/zsetup; }
    [ -n "$core" ] && [ -x "$core" ] || task_stop blocked missing-zsetup 127
    version=$("$core" --version) || task_stop blocked invalid-zsetup 11
    local core_pattern='^zsetup ([0-9]+)\.([0-9]+)\.([0-9]+)$'
    [[ "$version" =~ $core_pattern ]] || task_stop blocked invalid-zsetup 11
    [ "${BASH_REMATCH[1]}" -gt 0 ] || [ "${BASH_REMATCH[2]}" -ge 5 ] || task_stop blocked bounded-download-core-required 18
    if command -v uci >/dev/null 2>&1; then
        super_arch=$(uci -q get istore.istore.super_arch 2>/dev/null || true)
        channel=$(uci -q get istore.istore.channel 2>/dev/null || true)
    fi
    if [ -r "$root/etc/.app_store.id" ]; then
        model_arch=$("$task_jq" -r '.arch//""' "$root/etc/.app_store.id" 2>/dev/null) || model_arch=
        device_id=$("$task_jq" -r '.uid//""' "$root/etc/.app_store.id" 2>/dev/null) || device_id=
    fi
    api=https://istore.istoreos.com/api/store/list
    query=$("$task_jq" -nr --arg arch "$super_arch" --arg model "$model_arch" --arg channel "$channel" --arg device "$device_id" \
        '{tag:"default",sort:"default",search:"",limit:"1000",offset:"0",hide_docker:"false",ignore_arch:"false",super_arch:$arch,modelArch:$model,channel:$channel,deviceId:$device}|to_entries|map((.key|@uri)+"="+(.value|@uri))|join("&")')
    TASK_STORE_TMP=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/zsetup-store.XXXXXX") || task_stop failed catalog-staging-failed 12
    trap 'rm -rf "$TASK_STORE_TMP"' EXIT
    trap 'exit 130' INT; trap 'exit 143' TERM
    # Query parameters and native diagnostics may contain a device identity.
    # Keep them out of stdout/stderr consumed by the model, including failures.
    "$core" download --quiet --max-bytes 2097152 --min-free-bytes 1048576 --overall-timeout 20s \
        -o "$TASK_STORE_TMP/catalog.json" "$api?$query" >"$TASK_STORE_TMP/native.log" 2>&1 || code=$?
    if [ "$code" != 0 ]; then
        # Stable native categories; do not parse credential-bearing diagnostics.
        local category=native
        case "$code" in
            13) category=dns ;; 14) category=tls ;; 15) category=timeout ;;
            11) category=integrity ;; 12) category=filesystem ;;
            10) category=http-or-transfer ;; 130) category=canceled ;;
        esac
        task_stop failed store-catalog-unavailable "$code" "$("$task_jq" -cn --arg category "$category" '{stage:"catalog-download",source:"istore-store-api",failureCategory:$category}')"
    fi
    "$task_jq" -e '.result.apps|type=="array" and length<=2000' "$TASK_STORE_TMP/catalog.json" >/dev/null 2>&1 || task_stop failed invalid-store-catalog 11
    local matches count
    matches=$("$task_jq" -c --arg name "$TASK_SOFTWARE" --arg operation "$TASK_OPERATION" '[.result.apps[]|select((.name|type)=="string")|select(if $operation=="inspect" then (.name|ascii_downcase)==($name|ascii_downcase) else .name==$name end)]' "$TASK_STORE_TMP/catalog.json") || task_stop failed invalid-store-catalog 11
    count=$("$task_jq" -r length <<< "$matches")
    [ "$count" -le 1 ] || task_stop needs-ai ambiguous-software-identity 0
    TASK_STORE_APP=$("$task_jq" -c --arg arch "$super_arch" 'if length==1 then .[0]|{name,version,release,depends,arch,compatibility:(if ((.arch//[])|index("all"))!=null or ($arch!="" and ((.arch//[])|index($arch))!=null) then "supported" else "unknown" end)} else null end' <<< "$matches")
    TASK_STORE_SOURCE=$("$task_jq" -cn --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{id:"istore-store-api",freshness:"live",fetchedAt:$time,authority:"target-filtered-business-catalog"}')
    TASK_STORE_CATALOG_FOR=$TASK_SOFTWARE
}
