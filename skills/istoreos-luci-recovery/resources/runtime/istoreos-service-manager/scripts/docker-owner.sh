#!/usr/bin/env bash
# Internal bounded postcondition: kernel socket owner belongs to procd's PIDs.
# No service start, dependency installation, source execution or repair.
set -euo pipefail
[ "$#" = 3 ] || exit 2
record=$1 service=$2 endpoint=$3
socket=${endpoint#unix://}
[ "$socket" != "$endpoint" ] && [ -S "$socket" ] || exit 1
physical=$(readlink -f -- "$socket") || exit 1
[ -r /proc/net/unix ] || exit 1
mapfile -t service_pids < <(jq -er --arg service "$service" '
 [.[$service].instances//{}|.[]] as $instances|
 if ($instances|length)>0 and ($instances|all(.running==true and (.pid|type=="number" and .>0 and floor==.)))
 then $instances[].pid else empty end' "$record")
[ "${#service_pids[@]}" -gt 0 ] && [ "${#service_pids[@]}" -le 64 ] || exit 1
declare -A selected=() inodes=()
for pid in "${service_pids[@]}"; do selected[$pid]=1; done
# /proc/net/unix supplies a kernel socket inode, distinct from the filesystem inode.
while read -r number refs protocol flags type state inode path; do
    [ "$path" = "$socket" ] || [ "$path" = "$physical" ] || continue
    [[ "$inode" =~ ^[0-9]+$ ]] || continue
    inodes[$inode]=1
done < /proc/net/unix
[ "${#inodes[@]}" -gt 0 ] || exit 1
count=0
for process in /proc/[0-9]*; do
    ((count+=1));[ "$count" -le 4096 ] || exit 1
    pid=${process##*/};ancestor=$pid;bound=
    for ((depth=0;depth<32;depth++)); do
        if [ -n "${selected[$ancestor]:-}" ]; then bound=$ancestor;break;fi
        [ "$ancestor" -gt 1 ] && [ -r "/proc/$ancestor/status" ] || break
        parent=
        while read -r key value rest; do
            if [ "$key" = PPid: ]; then parent=$value;break;fi
        done < "/proc/$ancestor/status" 2>/dev/null || break
        [[ "$parent" =~ ^[0-9]+$ ]] && [ "$parent" != "$ancestor" ] || break
        ancestor=$parent
    done
    [ -n "$bound" ] || continue
    for descriptor in "$process"/fd/*; do
        link=$(readlink -- "$descriptor" 2>/dev/null) || continue
        [[ "$link" =~ ^socket:\[([0-9]+)\]$ ]] || continue
        inode=${BASH_REMATCH[1]}
        [ -n "${inodes[$inode]:-}" ] || continue
        jq -cn --argjson owner "$pid" --argjson servicePid "$bound" --arg inode "$inode" \
           '{socketOwnerPID:$owner,servicePID:$servicePid,kernelSocketInode:$inode,scope:"selected procd process or descendant owns endpoint"}'
        exit 0
    done
done
exit 1
