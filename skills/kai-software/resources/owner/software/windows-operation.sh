# Reuse a consumer's existing native operation adapter; never duplicate its
# Scoop ownership, prepared downloads, uninstall or receipt implementation.
task_windows_contract() {
    local manager dir script resource= resource_sha= core client policy root identity
    manager=$("$task_jq" -r .manager <<< "$TASK_NATIVE")
    case "$manager" in scoop|winget) ;; *) task_stop blocked unsupported-native-provider 0 ;; esac
    dir=${ZSETUP_TASK_WINDOWS_ADAPTER_DIR:-$task_root/windows}
    if command -v cygpath >/dev/null 2>&1; then dir=$(cygpath -u "$dir"); fi
    script="$dir/$manager.ps1"
    [ -f "$script" ] && [ ! -L "$script" ] || task_stop needs-ai native-write-adapter-required 0
    if [ "$manager" = scoop ]; then
        resource="$dir/../resources/scoop.lock.json"
        [ -f "$resource" ] && [ ! -L "$resource" ] || task_stop needs-ai native-provider-resources-required 0
        resource_sha=$(task_digest "$resource")
    fi
    core=${KAI_ZSETUP_BIN:-${ZSETUP_BIN:-$(type -P zsetup || type -P zsetup.exe || true)}}
    client=${KAI_KSCLI_BIN:-$(type -P ks-cli || type -P ks-cli.exe || true)}
    [ -n "$core" ] || { [ ! -x "$HOME/.local/bin/zsetup.exe" ] || core=$HOME/.local/bin/zsetup.exe; }
    [ -n "$client" ] || { [ ! -x "$HOME/.local/bin/ks-cli.exe" ] || client=$HOME/.local/bin/ks-cli.exe; }
    if command -v cygpath >/dev/null 2>&1; then
        [ -z "$core" ] || core=$(cygpath -u "$core")
        [ -z "$client" ] || client=$(cygpath -u "$client")
    fi
    if [ "$("$task_jq" -r '.intent//"install"' <<< "$TASK_REQUEST_JSON")" != remove ]; then
        [ -n "$client" ] && [ -x "$client" ] || task_stop needs-ai missing-provider-execution-client 127 '{"requiredProgram":"ks-cli"}'
        if [ "$manager" = scoop ]; then [ -n "$core" ] && [ -x "$core" ] || task_stop needs-ai missing-zsetup 127; fi
    fi
    if command -v cygpath >/dev/null 2>&1; then
        [ -z "$core" ] || core=$(cygpath -w "$core")
        [ -z "$client" ] || client=$(cygpath -w "$client")
    fi
    root=$("$task_jq" -r '.providerRoot//""' <<< "$TASK_NATIVE")
    identity=$("$task_jq" -r '.nativeId//""' <<< "$TASK_NATIVE")
    [ -n "$identity" ] || task_stop needs-ai native-provider-identity-required 0
    policy=$("$task_jq" -r '.acceleration//"auto"' <<< "$TASK_REQUEST_JSON")
    case "$policy" in auto|required|none) ;; *) task_stop invalid invalid-acceleration-policy 2 ;; esac
    TASK_WINDOWS_SCRIPT=$script
    TASK_WINDOWS_CONTRACT=$("$task_jq" -cn --arg manager "$manager" --arg digest "$(task_digest "$script")" --arg resources "$resource_sha" --arg root "$root" --arg identity "$identity" --arg core "$core" --arg client "$client" --arg policy "$policy" \
        '{manager:$manager,adapterDigest:$digest,resourceDigest:$resources,root:$root,nativeId:$identity,zsetup:$core,ksCli:$client,policy:$policy}')
}
task_windows_operation() {
    local action=$1 version=${2:-} reviewed=$TASK_WINDOWS_REVIEWED_CONTRACT script ps request code=0
    task_windows_contract
    [ "$("$task_jq" -cS . <<< "$reviewed")" = "$("$task_jq" -cS . <<< "$TASK_WINDOWS_CONTRACT")" ] || task_stop blocked native-provider-contract-changed 0
    script=$TASK_WINDOWS_SCRIPT; ps=$(type -P powershell.exe || true)
    [ -n "$ps" ] || task_stop blocked missing-native-powershell 127
    if command -v cygpath >/dev/null 2>&1; then script=$(cygpath -w "$script"); fi
    request=$("$task_jq" -c --arg action "$action" --arg version "$version" --arg runtime "${KAI_KSPEEDER_RUNTIME_BINARY:-}" --arg identity "${KAI_KSPEEDER_RUNTIME_IDENTITY:-}" \
        '{action:$action,subject:.nativeId,version:$version,root,ksCli,zsetup,policy,runtimeBinary:$runtime,runtimeIdentity:$identity}' <<< "$TASK_WINDOWS_CONTRACT")
    TASK_WINDOWS_TMP=$(umask 077;mktemp -d "${TMPDIR:-/tmp}/zsetup-windows.XXXXXX") || task_stop failed provider-staging-failed 12
    trap 'rm -rf "$TASK_WINDOWS_TMP"' EXIT
    trap 'exit 130' INT;trap 'exit 143' TERM
    printf '%s\n' 'Applying the reviewed operation through the selected Windows provider.' >&2
    printf '%s' "$request" | MSYS2_ARG_CONV_EXCL='*' "$ps" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$script" >"$TASK_WINDOWS_TMP/result.json" 2>"$TASK_WINDOWS_TMP/diagnostics.log" || code=$?
    [ "$code" = 0 ] || task_stop failed native-provider-operation-failed "$code" '{"verificationRequired":true}'
    [ "$(wc -c < "$TASK_WINDOWS_TMP/result.json")" -le 65536 ] || task_stop needs-ai provider-result-too-large 0 '{"verificationRequired":true}'
    "$task_jq" -e 'type=="object" and (.status//"passed")!="failed" and (.exitCode//0)==0' "$TASK_WINDOWS_TMP/result.json" >/dev/null 2>&1 || task_stop failed invalid-provider-operation-receipt 0 '{"verificationRequired":true}'
}
