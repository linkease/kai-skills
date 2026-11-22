# Native package ownership stays with the original manager. Queries do not refresh.
task_native_rows() {
    local source=$1 needle=${2:-} name description count=0 rows='[]'
    while read -r name description; do
        [ -n "$name" ] || continue
        case "$name $description" in *"$needle"*) ;; *) continue ;; esac
        [ "$count" -lt 20 ] || continue
        rows=$("$task_jq" -cn --argjson rows "$rows" --arg name "$name" --arg description "$description" --arg source "$source" '$rows+[{id:($source+":"+$name),name:$name,description:$description,source:$source}]')
        count=$((count + 1))
    done
    printf '%s\n' "$rows"
}
task_native_search() {
    local rows manager code=0
    if command -v apt-cache >/dev/null 2>&1; then
        manager=apt; rows=$(LC_ALL=C apt-cache search --names-only -- "$TASK_SOFTWARE" | task_native_rows apt) || code=$?
    elif command -v opkg >/dev/null 2>&1; then
        manager=opkg; rows=$(opkg list | task_native_rows opkg "$TASK_SOFTWARE") || code=$?
    elif command -v apk >/dev/null 2>&1; then
        manager=apk; rows=$(apk search -q -- "$TASK_SOFTWARE" | task_native_rows apk) || code=$?
    elif command -v brew >/dev/null 2>&1; then
        manager=brew; rows=$(HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 brew search --formula -- "$TASK_SOFTWARE" | task_native_rows brew) || code=$?
    elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
        manager=$(command -v dnf || command -v yum); rows=$("$manager" -q -C repoquery --qf '%{name} %{summary}' -- "*$TASK_SOFTWARE*" | task_native_rows rpm) || code=$?
    else task_stop needs-ai no-search-provider 0; fi
    [ "$code" = 0 ] || task_stop failed provider-search-failed "$code"
    task_result success searched 0 "$("$task_jq" -cn --arg manager "$manager" --argjson rows "$rows" '{manager:$manager,candidates:$rows,indexPolicy:"existing-provider-cache",limit:20}')"
}
task_native_query() {
    local native_name=${1:-$TASK_SOFTWARE} installed= candidate= manager= native_extra='{}'
    . "$task_root/platform.sh"
    task_platform
    manager=$TASK_MANAGER
    case "$manager" in
        apt|opkg|apk|dnf|yum) . "$task_root/native-linux.sh"; task_query_linux ;;
        brew) . "$task_root/native-brew.sh"; task_query_brew ;;
        windows) . "$task_root/native-windows.sh"; task_query_windows ;;
    esac
    TASK_NATIVE=$("$task_jq" -cn --arg manager "$manager" --arg candidate "$candidate" --arg installed "$installed" --argjson extra "$native_extra" '{manager:$manager,candidateVersion:$candidate,installedVersion:$installed}+$extra')
}
task_native_install() {
    local manager=$1 version=$2 code=0
    case "$manager" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::=--force-confold -- "$TASK_SOFTWARE=$version" >&2 || code=$? ;;
        opkg) opkg install "$TASK_SOFTWARE" >&2 || code=$? ;;
        apk) apk add -- "$TASK_SOFTWARE=$version" >&2 || code=$? ;;
        dnf|yum) "$manager" -y -C install -- "$TASK_SOFTWARE-$version" >&2 || code=$? ;;
        brew) HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 brew install --formula "$TASK_SOFTWARE" >&2 || code=$? ;;
        scoop|winget) . "$task_root/windows-operation.sh";task_windows_operation install "$version";return ;;
        *) task_stop blocked unsupported-native-provider 0 ;;
    esac
    [ "$code" = 0 ] || task_stop failed provider-install-failed "$code"
}

task_native_remove() {
    local manager=$1 code=0
    case "$manager" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get -o APT::Get::AutomaticRemove=false remove -y -- "$TASK_SOFTWARE" >&2 || code=$? ;;
        opkg) opkg remove "$TASK_SOFTWARE" >&2 || code=$? ;;
        apk) apk del -- "$TASK_SOFTWARE" >&2 || code=$? ;;
        dnf) dnf -y --noautoremove remove -- "$TASK_SOFTWARE" >&2 || code=$? ;;
        yum) yum -y --setopt=clean_requirements_on_remove=0 remove -- "$TASK_SOFTWARE" >&2 || code=$? ;;
        brew) HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 brew uninstall --formula "$TASK_SOFTWARE" >&2 || code=$? ;;
        scoop|winget) . "$task_root/windows-operation.sh";task_windows_operation remove;return ;;
        *) task_stop blocked unsupported-native-provider 0 ;;
    esac
    [ "$code" = 0 ] || task_stop failed provider-remove-failed "$code"
}
