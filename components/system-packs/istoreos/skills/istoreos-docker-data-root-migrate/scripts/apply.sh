#!/usr/bin/env bash
# Copy one explicitly selected, quiescent Docker data directory. Configuration
# and service changes are separate operations selected by the caller.
set -euo pipefail
op_name=docker.data.copy
op_here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$op_here/../../istoreos-service-manager/scripts/write-lib.sh"
[ "$#" = 1 ] || op_fail INVALID_ARGUMENT 'Usage: apply.sh REQUEST_JSON; a destination alone is insufficient.' 2
op_init "$1"
jq -e '.parameters|((keys-["operationId","source","destination","sourceIdentity","destinationIdentity","destinationParentIdentity","serviceName","endpoint","maxSourceBytes","reserveBytes","timeoutSeconds"])|length==0) and
  ([.source,.destination]|all(type=="string" and startswith("/") and length>1 and length<=256 and (test("[\u0000-\u001f]")|not))) and
  ([.sourceIdentity,.destinationIdentity,.destinationParentIdentity]|all(type=="string" and length>0 and length<=200)) and
  (.serviceName|type=="string" and test("^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$") and (contains("..")|not)) and
  (.endpoint|type=="string" and startswith("unix:///") and (test("[?@\u0000-\u001f]")|not)) and
  (.maxSourceBytes|type=="number" and .==floor and .>0 and .<=1000000000000000) and
  (.reserveBytes|type=="number" and .==floor and .>=0 and .<=1000000000000000)' <<< "$op_request" >/dev/null || op_fail INVALID_ARGUMENT 'Explicit source, destination, observed filesystem identities, local engine endpoint and copy budget are required.' 2
[ "${KAIPLUS_CONFIRMED:-}" = 1 ] || op_fail AUTHORIZATION_REQUIRED 'An existing scoped authorization marker is required; it does not grant host permissions.' 2
op_executor
for program in rsync stat du df find pidof ubus docker; do command -v "$program" >/dev/null 2>&1 || op_fail DEPENDENCY_UNAVAILABLE 'A declared native copy/quiescence dependency is unavailable; no fallback or installation was attempted.' 2; done
copy_source=$(jq -r .parameters.source <<< "$op_request")
copy_destination=$(jq -r .parameters.destination <<< "$op_request")
copy_parent=$(dirname -- "$copy_destination")
copy_endpoint=$(jq -r .parameters.endpoint <<< "$op_request")
copy_service=$(jq -r .parameters.serviceName <<< "$op_request")
copy_source_identity=$(jq -r .parameters.sourceIdentity <<< "$op_request")
copy_destination_identity=$(jq -r .parameters.destinationIdentity <<< "$op_request")
copy_parent_identity=$(jq -r .parameters.destinationParentIdentity <<< "$op_request")
copy_identity() {
    local inode filesystem
    inode=$(stat -c '%d:%i' -- "$1") || return 1
    filesystem=$(stat -f -c '%t:%i' -- "$1") || return 1
    printf '%s:%s\n' "$inode" "$filesystem"
}
copy_check_identity() {
    local actual
    actual=$(copy_identity "$1") || op_fail PRECONDITION_UNAVAILABLE 'A filesystem identity could not be read.'
    [ "$actual" = "$2" ] || op_fail PRECONDITION_CHANGED 'A declared directory or backing filesystem changed after observation.'
}
copy_empty() {
    local entries
    shopt -s nullglob dotglob
    entries=("$copy_destination"/*)
    shopt -u nullglob dotglob
    [ "${#entries[@]}" = 0 ] || op_fail DESTINATION_NOT_EMPTY 'Existing data sets are never merged, overwritten or deleted by this copy operation.'
}
copy_quiescent() {
    local code
    code=0;op_native pidof dockerd || code=$?
    [ "$code" = 1 ] || { [ "$code" != 0 ] || op_fail SOURCE_ACTIVE 'A local Docker daemon is still running; no service was stopped by this operation.'; op_fail QUIESCENCE_UNKNOWN 'Docker process absence could not be established.'; }
    op_native ubus call service list "$(jq -cn --arg name "$copy_service" '{name:$name}')" || op_fail QUIESCENCE_UNKNOWN 'Native service-manager state could not be read.'
    jq -e --arg service "$copy_service" 'type=="object" and ([.[$service].instances//{}|.[]]|all(.[];.running==false))' "$op_job/native.stdout" >/dev/null || op_fail SOURCE_ACTIVE 'The selected native service still has active instances.'
    code=0
    op_native env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH docker --host "$copy_endpoint" info --format '{{.ID}}' || code=$?
    [ "$code" != 0 ] || op_fail SOURCE_ACTIVE 'The explicitly selected local Docker engine API is reachable.'
    case "$code" in 124|126|137|143) op_fail QUIESCENCE_UNKNOWN 'The engine absence probe did not complete within its bounds.' ;; esac
    if grep -Eiq 'permission denied|access.*denied|certificate|TLS' "$op_job/native.stderr"; then op_fail QUIESCENCE_UNKNOWN 'Engine access failed without establishing that the engine is stopped.'; fi
    grep -Eiq 'cannot connect to the docker daemon|connection refused|no such file or directory' "$op_job/native.stderr" || op_fail QUIESCENCE_UNKNOWN 'The engine response does not establish an unavailable local API.'
}
[ -d "$copy_source" ] && [ ! -L "$copy_source" ] && [ "$(CDPATH= cd -- "$copy_source" && pwd -P)" = "$copy_source" ] || op_fail INVALID_ARGUMENT 'Source must be an existing physical directory.' 2
[ -d "$copy_parent" ] && [ ! -L "$copy_parent" ] && [ "$(CDPATH= cd -- "$copy_parent" && pwd -P)" = "$copy_parent" ] || op_fail INVALID_ARGUMENT 'Destination parent must be an existing physical directory.' 2
case "$copy_destination/" in "$copy_source/"*) op_fail INVALID_ARGUMENT 'Source and destination must not overlap.' 2 ;; esac
case "$copy_source/" in "$copy_destination/"*) op_fail INVALID_ARGUMENT 'Source and destination must not overlap.' 2 ;; esac
case "$op_job/" in "$copy_source/"*|"$copy_destination/"*) op_fail CONTEXT_UNAVAILABLE 'Operation journals must be outside the copied directories.' 2 ;; esac
copy_check_identity "$copy_source" "$copy_source_identity"
copy_check_identity "$copy_parent" "$copy_parent_identity"
if [ -e "$copy_destination" ] || [ -L "$copy_destination" ]; then
    [ -d "$copy_destination" ] && [ ! -L "$copy_destination" ] && [ "$(CDPATH= cd -- "$copy_destination" && pwd -P)" = "$copy_destination" ] || op_fail INVALID_ARGUMENT 'Existing destination must be a physical directory.' 2
    copy_check_identity "$copy_destination" "$copy_destination_identity"
    copy_empty
else
    [ "$copy_destination_identity" = absent ] || op_fail PRECONDITION_CHANGED 'The observed destination no longer exists.'
fi
copy_quiescent
# Nested mounts and sockets would make an ordinary directory copy incomplete.
op_native env KAI_COPY_SCOPE="$copy_source" awk '
  BEGIN {root=ENVIRON["KAI_COPY_SCOPE"]}
  {p=$5;gsub(/\\040/," ",p);gsub(/\\011/,"\t",p);gsub(/\\134/,"\\",p);if(index(p,root"/")==1) found=1}
  END {exit found}' /proc/self/mountinfo || op_fail NESTED_MOUNT 'Source contains a nested mount or mount observation failed; no partial filesystem traversal was accepted.'
op_native find "$copy_source" -xdev -type s -print -quit || op_fail PRECONDITION_UNAVAILABLE 'Source entry types could not be inspected.'
[ ! -s "$op_job/native.stdout" ] || op_fail UNSUPPORTED_SOURCE_ENTRY 'Source contains a socket; it cannot be represented by this copy contract.'
op_native du -sk -- "$copy_source" || op_fail PRECONDITION_UNAVAILABLE 'Source allocated size could not be read.'
copy_kib=$(awk 'NR==1{print $1}' "$op_job/native.stdout")
[[ "$copy_kib" =~ ^[0-9]+$ ]] || op_fail PRECONDITION_UNAVAILABLE 'Native source size was not a bounded integer.'
copy_bytes=$((copy_kib*1024))
[ "$copy_bytes" -le "$(jq -r .parameters.maxSourceBytes <<< "$op_request")" ] || op_fail COPY_BUDGET_EXCEEDED 'Source exceeds the explicitly selected preflight budget.'
op_native df -Pk -- "$copy_parent" || op_fail PRECONDITION_UNAVAILABLE 'Destination free space could not be read.'
copy_free_kib=$(awk 'NR==2{print $4}' "$op_job/native.stdout")
[[ "$copy_free_kib" =~ ^[0-9]+$ ]] || op_fail PRECONDITION_UNAVAILABLE 'Native destination free space was not a bounded integer.'
[ "$((copy_free_kib*1024-copy_bytes))" -ge "$(jq -r .parameters.reserveBytes <<< "$op_request")" ] || op_fail INSUFFICIENT_SPACE 'Observed destination space does not cover the source estimate and explicit reserve.'
op_fact copyScope "$(jq -cn --arg source "$copy_source" --arg destination "$copy_destination" --argjson bytes "$copy_bytes" '{source:$source,destination:$destination,allocatedSourceBytes:$bytes,budgetKind:"preflight-estimate-no-quota",externalBindData:"not-included",configurationChanged:false,servicesChanged:false}')" 'explicit paths, native directory identities, du and df; no whole-migration success claim'
if [ "$copy_destination_identity" = absent ]; then op_effect destination-create create-directory "$copy_destination"; fi
op_effect data-copy copy-directory "$copy_destination"
copy_check_identity "$copy_source" "$copy_source_identity"
copy_check_identity "$copy_parent" "$copy_parent_identity"
if [ "$copy_destination_identity" = absent ]; then op_run_effect destination-create mkdir -- "$copy_destination"; else copy_empty; fi
op_run_effect data-copy rsync -aHAXS --numeric-ids --one-file-system -- "$copy_source/" "$copy_destination/"
# --delete is used only in a dry run, so unexpected destination extras fail
# verification rather than being removed.
op_native rsync -aHAXSnc --numeric-ids --one-file-system --delete --itemize-changes --dry-run -- "$copy_source/" "$copy_destination/" || op_fail VERIFICATION_UNAVAILABLE 'Native content/attribute verification failed.'
copy_match=false;[ -s "$op_job/native.stdout" ] || copy_match=true
op_check contents-and-properties "$copy_match" 'native checksum, metadata, ACL, xattr, hardlink and symlink comparison; deletion is dry-run only'
copy_check_identity "$copy_source" "$copy_source_identity"
copy_check_identity "$copy_parent" "$copy_parent_identity"
copy_quiescent
op_check source-quiescent true 'local Docker process absent, selected procd instances stopped and selected local API unavailable'
op_success
