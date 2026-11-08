# Fast path facts only: no recursive scans, directory creation or disk cleanup.
task_storage_fact() {
    local path=$1 physical line source total used available capacity mountpoint
    local filesystem identity inode_free=null persistence=verified-filesystem role=${2:-}
    local entry_source entry_mount entry_fs entry_options entry_rest best_length=0 best_options=
    case "$path" in /*) ;; *) return 2 ;; esac
    [ -d "$path" ] && [ ! -L "$path" ] && [ -w "$path" ] && [ -x "$path" ] || return 2
    physical=$(CDPATH= cd -- "$path" && pwd -P) || return 2
    [ "$physical" = "$path" ] || return 2
    line=$(LC_ALL=C df -Pk "$path" | tail -n 1) || return 12
    read -r source total used available capacity mountpoint <<< "$line"
    case "$available" in ''|*[!0-9]*) return 12 ;; esac
    identity=$(stat -c '%d:%i' "$path" 2>/dev/null) || identity=$(stat -f '%d:%i' "$path" 2>/dev/null) || return 12
    filesystem=$(stat -f -c '%T' "$path" 2>/dev/null) || filesystem=
    case "$(uname -s):$filesystem" in
        MINGW*:*|MSYS*:*|CYGWIN*:*)
            # MSYS statfs may expose UNKNOWN for native NTFS. Ask the actual
            # local Windows volume, not the controller or the drive label.
            local native_path drive
            native_path=$(cygpath -w "$path") || return 19
            drive=${native_path:0:1}
            case "$drive" in [A-Za-z]) ;; *) return 19 ;; esac
            filesystem=$(MSYS2_ARG_CONV_EXCL='*' powershell.exe -NoLogo -NoProfile -NonInteractive -Command \
                "\$ProgressPreference='SilentlyContinue'; \$v=Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='$drive:'\"; if(\$v.DriveType -ne 3){exit 19}; [Console]::WriteLine(\$v.FileSystem.ToLowerInvariant())") || return 19
            filesystem=${filesystem//$'\r'/}
            ;;
    esac
    if [ -r /proc/mounts ]; then
        while read -r entry_source entry_mount entry_fs entry_options entry_rest; do
            entry_mount=$(printf '%b' "$entry_mount")
            case "$path" in "$entry_mount"|"${entry_mount%/}/"*)
                if [ "${#entry_mount}" -gt "$best_length" ]; then best_length=${#entry_mount}; best_options=$entry_options; fi ;;
            esac
        done < /proc/mounts
        case ",$best_options," in *,ro,*|*,noexec,*) return 2 ;; esac
    fi
    if [ -z "$filesystem" ]; then
        while IFS= read -r line; do
            case "$line" in *" on $mountpoint ("*) filesystem=${line##* (}; filesystem=${filesystem%%,*}; filesystem=${filesystem%)}; break ;; esac
        done < <(mount)
    fi
    case "$filesystem" in ext2/ext3|ext4|xfs|btrfs|zfs|apfs|hfs|hfsplus|ntfs|ntfs3|refs) ;;
        overlay|overlayfs|aufs)
            # Native packages cannot be relocated to a portable prefix. An
            # explicit system-root budget remains separate from data volumes.
            [ "$path" = / ] && [ "$role" = system-package ] && \
                [ "$("$task_jq" -r '.method//""' <<< "$TASK_REQUEST_JSON")" = native-package ] || return 19
            persistence=system-root ;;
        *) return 19 ;;
    esac
    case "$(uname -s)" in Linux) inode_free=$(stat -f -c '%d' "$path" 2>/dev/null) || inode_free=null ;; esac
    "$task_jq" -cn --arg path "$path" --arg source "$source" --arg mount "$mountpoint" \
        --arg identity "$identity" --arg filesystem "$filesystem" --argjson available "$((available * 1024))" \
        --argjson inodes "$inode_free" --arg persistence "$persistence" '{path:$path,volume:($source+":"+$mount),directoryIdentity:$identity,filesystem:$filesystem,freeBytes:$available,freeInodes:$inodes,persistence:$persistence}'
}
task_storage_plan() {
    local observations='[]' count index=0 item path bytes facts code reserve required
    "$task_jq" -e '.storage|type=="object" and (.paths|type=="array" and length>0 and length<=32 and all(.[];(.path|type=="string" and length>0 and length<=4096) and (.role|type=="string") and (.bytes|type=="number" and floor==. and .>=0 and .<=1000000000000000) and ((.inodes//0)|type=="number" and floor==. and .>=0))) and ((.reserveBytes//8388608)|type=="number" and floor==. and .>=0 and .<=1000000000000000)' <<< "$TASK_REQUEST_JSON" >/dev/null 2>&1 || task_stop invalid invalid-storage-budget 2
    count=$("$task_jq" '.storage.paths|length' <<< "$TASK_REQUEST_JSON")
    reserve=$("$task_jq" '.storage.reserveBytes//8388608' <<< "$TASK_REQUEST_JSON")
    while [ "$index" -lt "$count" ]; do
        item=$("$task_jq" -c ".storage.paths[$index]" <<< "$TASK_REQUEST_JSON")
        path=$("$task_jq" -r .path <<< "$item")
        facts=$(task_storage_fact "$path" "$("$task_jq" -r .role <<< "$item")"); code=$?
        case "$code" in 0) ;; 19) task_stop blocked unverified-persistent-storage "$code" ;; *) task_stop blocked unsafe-storage-path "$code" ;; esac
        observations=$("$task_jq" -cn --argjson previous "$observations" --argjson item "$item" --argjson facts "$facts" '$previous+[$facts+{role:$item.role,bytes:$item.bytes,inodes:($item.inodes//0)}]')
        index=$((index + 1))
    done
    TASK_STORAGE_VOLUMES=$("$task_jq" -c --argjson reserve "$reserve" 'sort_by(.volume)|group_by(.volume)|map({volume:.[0].volume,freeBytes:(map(.freeBytes)|min),freeInodes:.[0].freeInodes,requiredBytes:((map(.bytes)|add)+$reserve),requiredInodes:(map(.inodes)|add)})' <<< "$observations")
    "$task_jq" -e 'all(.[];.freeBytes>=.requiredBytes)' <<< "$TASK_STORAGE_VOLUMES" >/dev/null || task_stop blocked insufficient-space 0 "$TASK_STORAGE_VOLUMES"
    "$task_jq" -e 'all(.[];.requiredInodes==0 or (.freeInodes!=null and .freeInodes>=.requiredInodes))' <<< "$TASK_STORAGE_VOLUMES" >/dev/null || task_stop blocked insufficient-or-unknown-inodes 0 "$TASK_STORAGE_VOLUMES"
    TASK_STORAGE_PLAN=$("$task_jq" -cn --arg request "$(task_request_digest)" --arg owner "$(task_digest "$task_root/storage.sh")" --argjson paths "$observations" --argjson volumes "$TASK_STORAGE_VOLUMES" '{requestDigest:$request,ownerDigest:$owner,paths:$paths,volumes:$volumes}')
}
task_storage_check() {
    local expected old_identity actual_identity
    expected=${1:-$("$task_jq" -c '.storagePlan//null' <<< "$TASK_REQUEST_JSON")}
    [ "$expected" != null ] || task_stop blocked missing-storage-plan 0
    [ "$("$task_jq" -r .requestDigest <<< "$expected")" = "$(task_request_digest)" ] && \
        [ "$("$task_jq" -r .ownerDigest <<< "$expected")" = "$(task_digest "$task_root/storage.sh")" ] || task_stop blocked storage-plan-changed 0
    task_storage_plan
    old_identity=$("$task_jq" -c '[.paths[]|{path,volume,directoryIdentity,filesystem}]' <<< "$expected")
    actual_identity=$("$task_jq" -c '[.paths[]|{path,volume,directoryIdentity,filesystem}]' <<< "$TASK_STORAGE_PLAN")
    [ "$old_identity" = "$actual_identity" ] || task_stop blocked storage-identity-changed 0
}
