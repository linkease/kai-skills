# One native query. Never refresh indexes or interpret installed info as a feed.
task_query_linux() {
    local raw code=0 v
    case "$manager" in
        apt)
            raw=$(LC_ALL=C apt-cache policy -- "$native_name" 2>/dev/null) || code=$?
            [ "$code" = 0 ] || task_stop failed provider-query-failed "$code"
            candidate=$(awk '$1=="Candidate:" && $2!="(none)" {print $2;exit}' <<< "$raw")
            installed=$(awk '$1=="Installed:" && $2!="(none)" {print $2;exit}' <<< "$raw") ;;
        opkg)
            . "$task_root/native-opkg.sh"; task_opkg_candidate "$native_name"
            candidate=$("$task_jq" -r .candidateVersion <<< "$TASK_OPKG_CANDIDATE")
            native_extra=$("$task_jq" -c 'del(.candidateVersion)' <<< "$TASK_OPKG_CANDIDATE")
            raw=$(opkg status "$native_name" 2>/dev/null) || code=$?
            [ "$code" = 0 ] || task_stop failed provider-installed-query-failed "$code"
            installed=$(awk '$1=="Version:"{v=$2} /^Status:.* installed$/{print v;exit}' <<< "$raw") ;;
        apk)
            raw=$(apk policy "$native_name" 2>/dev/null) || code=$?
            [ "$code" = 0 ] || task_stop failed provider-query-failed "$code"
            candidate=$(awk '/^  [0-9][^ ]*:$/ {gsub(/:/,"",$1);print $1;exit}' <<< "$raw")
            if apk info -e "$native_name" >/dev/null 2>&1; then installed=$(apk info -v "$native_name"); installed=${installed#"$native_name"-}; fi ;;
        dnf|yum)
            raw=$("$manager" -q -C repoquery --latest-limit 1 --qf '%{version}-%{release}' -- "$native_name" 2>/dev/null) || code=$?
            [ "$code" = 0 ] || task_stop failed provider-query-failed "$code"
            candidate=$(head -n 1 <<< "$raw")
            installed=$(rpm -q --qf '%{VERSION}-%{RELEASE}' -- "$native_name" 2>/dev/null) || installed= ;;
    esac
}
