# Target facts only. A system-root override is for isolated inspection fixtures.
task_platform() {
    local root=${ZSETUP_TASK_SYSTEM_ROOT:-} opkg_db=0 apk_db=0
    TASK_PLATFORM=unknown; TASK_MANAGER=; TASK_STORE=false
    case "$root" in ''|/*) ;; *) task_stop invalid invalid-system-root 2 ;; esac
    case "$(uname -s)" in
        Darwin) TASK_PLATFORM=macos; command -v brew >/dev/null 2>&1 && TASK_MANAGER=brew ;;
        MINGW*|MSYS*|CYGWIN*) TASK_PLATFORM=windows; TASK_MANAGER=windows ;;
        Linux)
            TASK_PLATFORM=linux
            if [ -f "$root/etc/openwrt_release" ] || grep -Eiq '^ID=["\047]?(istoreos|openwrt)' "$root/etc/os-release" 2>/dev/null; then
                TASK_PLATFORM=openwrt
                [ ! -f "$root/usr/lib/opkg/status" ] || opkg_db=1
                [ ! -f "$root/lib/apk/db/installed" ] || apk_db=1
                [ ! -f "$root/usr/lib/apk/db/installed" ] || apk_db=1
                [ "$opkg_db:$apk_db" != 1:1 ] || task_stop needs-ai ambiguous-native-database 0
                if [ "$opkg_db" = 1 ] && command -v opkg >/dev/null 2>&1; then TASK_MANAGER=opkg
                elif [ "$apk_db" = 1 ] && command -v apk >/dev/null 2>&1; then TASK_MANAGER=apk
                else task_stop needs-ai native-database-required 0; fi
                command -v is-opkg >/dev/null 2>&1 && TASK_STORE=true
            elif command -v apt-cache >/dev/null 2>&1; then TASK_MANAGER=apt
            elif command -v opkg >/dev/null 2>&1; then TASK_MANAGER=opkg
            elif command -v apk >/dev/null 2>&1; then TASK_MANAGER=apk
            elif command -v dnf >/dev/null 2>&1; then TASK_MANAGER=dnf
            elif command -v yum >/dev/null 2>&1; then TASK_MANAGER=yum; fi ;;
    esac
    return 0
}
