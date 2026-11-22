# Native PowerShell owns source-specific queries. Request travels over stdin.
task_query_windows() {
    local ps script request raw code=0
    ps=$(type -P powershell.exe || true)
    [ -n "$ps" ] || task_stop blocked missing-native-powershell 127
    script="$task_root/native-windows.ps1"
    if command -v cygpath >/dev/null 2>&1; then script=$(cygpath -w "$script"); fi
    request=$("$task_jq" -c --arg name "$native_name" '.+{software:$name}' <<< "$TASK_REQUEST_JSON")
    raw=$(printf '%s' "$request" | MSYS2_ARG_CONV_EXCL='*' "$ps" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$script") || code=$?
    "$task_jq" -e 'type=="object"' <<< "$raw" >/dev/null 2>&1 || task_stop failed invalid-windows-query-result 11
    [ "$code" = 0 ] || task_stop needs-ai "$("$task_jq" -r '.reason//"native-query-unavailable"' <<< "$raw")" "$code" "$("$task_jq" -c '{stage,choices,unavailableProviders}' <<< "$raw")"
    manager=$("$task_jq" -r .manager <<< "$raw")
    installed=$("$task_jq" -r .installedVersion <<< "$raw")
    candidate=$("$task_jq" -r .candidateVersion <<< "$raw")
    native_extra=$("$task_jq" -c 'del(.manager,.installedVersion,.candidateVersion)' <<< "$raw")
}
