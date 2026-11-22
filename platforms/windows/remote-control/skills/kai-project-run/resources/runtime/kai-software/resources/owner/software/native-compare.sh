# Compare installed to candidate with the selected provider's own semantics.
task_native_compare() {
    local manager=$1 installed=$2 candidate=$3 order
    TASK_COMPARISON=unknown
    [ -n "$installed" ] && [ -n "$candidate" ] || return 0
    if [ "$installed" = "$candidate" ]; then TASK_COMPARISON=same; return 0; fi
    case "$manager" in
        opkg)
            if opkg compare-versions "$installed" '<' "$candidate"; then TASK_COMPARISON=candidate-newer
            elif opkg compare-versions "$installed" '>' "$candidate"; then TASK_COMPARISON=installed-newer; fi ;;
        apt)
            if dpkg --compare-versions "$installed" lt "$candidate"; then TASK_COMPARISON=candidate-newer
            elif dpkg --compare-versions "$installed" gt "$candidate"; then TASK_COMPARISON=installed-newer; fi ;;
        apk)
            order=$(apk version -t "$installed" "$candidate") || return 0
            case "$order" in '<') TASK_COMPARISON=candidate-newer ;; '>') TASK_COMPARISON=installed-newer ;; '=') TASK_COMPARISON=same ;; esac ;;
        brew)
            order=$("$task_jq" -r '.updateAvailable//false' <<< "$TASK_NATIVE")
            [ "$order" != true ] || TASK_COMPARISON=candidate-newer ;;
        scoop|winget) TASK_COMPARISON=$("$task_jq" -r '.comparison//"unknown"' <<< "$TASK_NATIVE") ;;
    esac
    return 0
}
