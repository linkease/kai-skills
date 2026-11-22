# opkg list/info include installed records. Read candidates only from configured
# feed cache files; opkg still owns architecture and version semantics.
task_opkg_candidate() {
    local name=$1 root=${ZSETUP_TASK_SYSTEM_ROOT:-} conf lists=/var/opkg-lists dirs= sources= arches=
    local source file version arch digest modified best= rows='[]' source_count=0 row_count=0
    for conf in "$root/etc/opkg.conf" "$root/etc/opkg/"*.conf; do
        [ -f "$conf" ] || continue
        dirs=$(awk '$1=="lists_dir"{print $NF}' "$conf")
        [ -z "$dirs" ] || lists=$(tail -n 1 <<< "$dirs")
        sources="$sources
$(awk '$1=="src" || $1=="src/gz"{print $2}' "$conf")"
    done
    case "$lists" in /*) ;; *) task_stop needs-ai unsupported-native-cache-location 0 ;; esac
    arches=$(opkg print-architecture 2>/dev/null | awk '$1=="arch"{printf " %s ",$2}') || task_stop failed native-architecture-query-failed "$?"
    while IFS= read -r source; do
        case "$source" in ''|*[!A-Za-z0-9._+-]*) continue ;; esac
        source_count=$((source_count+1)); [ "$source_count" -le 64 ] || task_stop needs-ai native-source-limit 0
        file="$root${lists%/}/$source"
        [ -f "$file" ] || continue
        modified=$(stat -c '%Y' "$file" 2>/dev/null) || modified=0
        while IFS=$'\t' read -r version arch digest; do
            [[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._+:~+-]{0,127}$ ]] || continue
            case "$arches" in *" $arch "*) ;; *) continue ;; esac
            row_count=$((row_count+1)); [ "$row_count" -le 64 ] || task_stop needs-ai native-candidate-limit 0
            [[ "$digest" =~ ^[a-fA-F0-9]{64}$ ]] || digest=
            if [ -z "$best" ] || opkg compare-versions "$version" '>' "$best"; then best=$version; fi
            rows=$("$task_jq" -cn --argjson rows "$rows" --arg source "$source" --arg version "$version" --arg sha "$(printf '%s' "$digest" | tr 'A-F' 'a-f')" --argjson modified "$modified" '$rows+[{feed:$source,version:$version,sha256:$sha,cacheModifiedUnix:$modified}]')
        done < <(awk -v name="$name" 'BEGIN{RS="";FS="\n"}
            {p="";v="";a="";h="";for(i=1;i<=NF;i++){
                if($i~/^Package: /)p=substr($i,10)
                else if($i~/^Version: /)v=substr($i,10)
                else if($i~/^Architecture: /)a=substr($i,15)
                else if($i~/^SHA256sum: /)h=substr($i,12)
            }if(p==name && v!="" && a!="")printf "%s\t%s\t%s\n",v,a,h}' "$file")
    done < <(printf '%s\n' "$sources" | sort -u)
    TASK_OPKG_CANDIDATE=$("$task_jq" -cn --arg version "$best" --argjson rows "$rows" \
        '{candidateVersion:$version,source:{id:"opkg-configured-feeds",freshness:"native-cache",fetchedAt:null,records:[$rows[]|select(.version==$version)]},sourceConflict:([$rows[]|select(.version==$version)|.sha256|select(test("^[a-f0-9]{64}$"))]|unique|length>1)}')
}
