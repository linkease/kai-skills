# Linkspace owns backup format, revisions, integrity and restoration.
task_backup_input_digest() {
    "$task_jq" -cS '{targetId,software,backup:(.backup|del(.revision,.restoreDir))}' <<< "$TASK_REQUEST_JSON" | task_hash_input
}
task_backup_plan() {
    local source base scope required consistency saved version code source_id directory_policy=required
    "$task_jq" -e '.backup|type=="object" and (.source|type=="string") and (.baseDir|type=="string") and (.scope=="system-config" or .scope=="application-config" or .scope=="application-data") and (.requiredBytes|type=="number" and floor==. and .>0 and .<=1000000000000000) and ((.timeoutSeconds//60)|type=="number" and floor==. and .>=1 and .<=300)' <<< "$TASK_REQUEST_JSON" >/dev/null 2>&1 || task_stop invalid invalid-backup-definition 2
    source=$("$task_jq" -r .backup.source <<< "$TASK_REQUEST_JSON");base=$("$task_jq" -r .backup.baseDir <<< "$TASK_REQUEST_JSON")
    scope=$("$task_jq" -r .backup.scope <<< "$TASK_REQUEST_JSON");required=$("$task_jq" -r .backup.requiredBytes <<< "$TASK_REQUEST_JSON")
    consistency=$("$task_jq" -r '.backup.consistency//"file-level"' <<< "$TASK_REQUEST_JSON")
    case "$source:$base" in /*:/*) ;; *) task_stop blocked unsafe-backup-path 0 ;; esac
    [ "$source" != / ] && [ -d "$source" ] && [ ! -L "$source" ] && [ "$(CDPATH= cd -- "$source" && pwd -P)" = "$source" ] || task_stop blocked unsafe-backup-source 0
    case "$base/" in "$source/"*) task_stop blocked backup-source-destination-overlap 0 ;; esac
    case "$source/" in "$base/"*) task_stop blocked backup-source-destination-overlap 0 ;; esac
    [ "$consistency" = file-level ] || task_stop needs-ai application-consistency-hook-required 0
    [ "$("$task_jq" -r '.backup.requiresApplicationConsistency//false' <<< "$TASK_REQUEST_JSON")" != true ] || task_stop needs-ai application-consistency-hook-required 0
    [ "$("$task_jq" -r '(.backup.excludes//[])|length' <<< "$TASK_REQUEST_JSON")" = 0 ] || task_stop needs-ai backup-exclusion-policy-required 0
    case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*)
        directory_policy='unsupported-directory-barrier; file-sync-retained'
        [ "$("$task_jq" -r '.backup.requiresDirectorySync//false' <<< "$TASK_REQUEST_JSON")" != true ] || task_stop needs-ai directory-sync-unavailable 0 ;;
    esac
    TASK_LINKSPACE=${LINKSPACE_BIN:-${KAI_LINKSPACE_BIN:-$(type -P linkspace || true)}}
    [ -n "$TASK_LINKSPACE" ] && [ -x "$TASK_LINKSPACE" ] || task_stop blocked missing-linkspace 127
    version=$("$TASK_LINKSPACE" backup version --json);code=$?
    [ "$code" = 0 ] && "$task_jq" -e '.result.version|type=="string"' <<< "$version" >/dev/null 2>&1 || task_stop blocked incompatible-linkspace "$code"
    saved=$TASK_REQUEST_JSON
    TASK_REQUEST_JSON=$("$task_jq" -c --arg base "$base" --argjson bytes "$required" '.storage={reserveBytes:8388608,paths:[{role:"backup-retention-and-work",path:$base,bytes:$bytes,inodes:0}]}' <<< "$TASK_REQUEST_JSON")
    task_storage_plan
    TASK_BACKUP_STORAGE=$TASK_STORAGE_PLAN
    TASK_REQUEST_JSON=$saved
    source_id=$(printf '%s\000%s\000%s' "$TASK_TARGET" "$scope" "$source" | task_hash_input)
    TASK_BACKUP_PLAN=$("$task_jq" -cn --arg source "$source" --arg base "$base" --arg scope "$scope" --arg sourceId "source-$source_id" --arg input "$(task_backup_input_digest)" --arg version "$("$task_jq" -r .result.version <<< "$version")" --argjson storage "$TASK_BACKUP_STORAGE" --arg directory "$directory_policy" \
        '{backend:"linkspace",backendVersion:$version,scope:$scope,source:$source,baseDir:$base,repository:($base+"/repository"),sourceId:$sourceId,inputDigest:$input,consistency:"file-level",applicationConsistencyVerified:false,directorySyncPolicy:$directory,excludes:[],budgetKind:"preflight-reservation",storagePlan:$storage,restorePolicy:"separate-new-directory"}')
}
task_backup_common_args() {
    TASK_BACKUP_BASE=$("$task_jq" -r .baseDir <<< "$TASK_BACKUP_PLAN")
    TASK_BACKUP_REPO=$("$task_jq" -r .repository <<< "$TASK_BACKUP_PLAN")
    TASK_BACKUP_TIMEOUT=$("$task_jq" -r '.backup.timeoutSeconds//60' <<< "$TASK_REQUEST_JSON")
}
task_backup_add_budget() {
    TASK_REQUEST_JSON=$("$task_jq" -c '.storage.reserveBytes=(.storage.reserveBytes//8388608)|.storage.paths=((.storage.paths//[])+[{role:"backup-retention-and-work",path:.backup.baseDir,bytes:.backup.requiredBytes,inodes:0}])' <<< "$TASK_REQUEST_JSON")
}
task_backup_call() {
    local result code
    result=$("$TASK_LINKSPACE" backup "$@" --target "$TASK_BACKUP_REPO" --state-dir "$TASK_BACKUP_BASE/state" --config-dir "$TASK_BACKUP_BASE/config" --timeout "${TASK_BACKUP_TIMEOUT}s" --non-interactive --json);code=$?
    [ "$code" = 0 ] || task_stop failed backup-failed "$code" "$("$task_jq" -c '{backend:"linkspace",command:.command,nativeError:.error}' <<< "$result" 2>/dev/null || printf '{}')"
    "$task_jq" -e '.status=="succeeded" and .result!=null' <<< "$result" >/dev/null 2>&1 || task_stop failed invalid-backup-result 11
    TASK_BACKUP_NATIVE=$result
}
task_backup_run() {
    local expected=${1:-} source revision repo_id
    task_backup_plan
    if [ -n "$expected" ]; then
        [ "$("$task_jq" -r .inputDigest <<< "$expected")" = "$(task_backup_input_digest)" ] || task_stop blocked backup-plan-changed 0
        [ "$("$task_jq" -c '.storagePlan.paths|map({path,volume,directoryIdentity,filesystem})' <<< "$expected")" = "$("$task_jq" -c '.storagePlan.paths|map({path,volume,directoryIdentity,filesystem})' <<< "$TASK_BACKUP_PLAN")" ] || task_stop blocked backup-storage-identity-changed 0
    fi
    task_backup_common_args
    TASK_EFFECTS='["backup-repository"]'
    if [ ! -e "$TASK_BACKUP_REPO" ]; then task_backup_call repo init --repo-id kai-software-backup; fi
    task_backup_call repo show
    repo_id=$("$task_jq" -r .result.repoID <<< "$TASK_BACKUP_NATIVE")
    [ "$repo_id" = kai-software-backup ] || task_stop blocked foreign-backup-repository 0
    source=$("$task_jq" -r .source <<< "$TASK_BACKUP_PLAN")
    task_backup_call run --source "$source" --source-id "$("$task_jq" -r .sourceId <<< "$TASK_BACKUP_PLAN")" --writer-id kai-software
    revision=$("$task_jq" -r .result.revisionID <<< "$TASK_BACKUP_NATIVE")
    [ -n "$revision" ] && [ "$revision" != null ] || task_stop failed invalid-backup-revision 11
    task_backup_call check
    "$task_jq" -e '(.result.check.findings//[])|length==0' <<< "$TASK_BACKUP_NATIVE" >/dev/null || task_stop failed backup-integrity-failed 11
    TASK_BACKUP_RECEIPT=$("$task_jq" -c --arg target "$TASK_TARGET" --arg software "$TASK_SOFTWARE" --arg revision "$revision" '.+{targetId:$target,software:$software,revisionId:$revision,integrityVerified:true,restoreVerified:false}' <<< "$TASK_BACKUP_PLAN")
}
task_backup_restore() {
    local receipt destination revision source_id saved
    receipt=$("$task_jq" -c '.backupReceipt//null' <<< "$TASK_REQUEST_JSON")
    [ "$receipt" != null ] || task_stop blocked missing-backup-receipt 0
    task_backup_plan;task_backup_common_args
    [ "$("$task_jq" -r .inputDigest <<< "$receipt")" = "$(task_backup_input_digest)" ] && \
        [ "$("$task_jq" -r .targetId <<< "$receipt")" = "$TASK_TARGET" ] || task_stop blocked backup-scope-mismatch 0
    revision=$("$task_jq" -r .revisionId <<< "$receipt")
    "$task_jq" -en --arg id "$revision" '$id|test("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,255}$")' >/dev/null || task_stop invalid invalid-backup-revision 2
    destination=$("$task_jq" -r '.backup.restoreDir//""' <<< "$TASK_REQUEST_JSON")
    case "$destination" in /*) ;; *) task_stop blocked unsafe-restore-path 0 ;; esac
    [ ! -e "$destination" ] && [ ! -L "$destination" ] && [ -d "${destination%/*}" ] || task_stop blocked restore-requires-new-directory 0
    [ "$(CDPATH= cd -- "${destination%/*}" && pwd -P)" = "${destination%/*}" ] || task_stop blocked unsafe-restore-path 0
    case "$destination/" in "$("$task_jq" -r .source <<< "$TASK_BACKUP_PLAN")/"*|"$TASK_BACKUP_BASE/"*) task_stop blocked unsafe-restore-path 0 ;; esac
    saved=$TASK_REQUEST_JSON
    TASK_REQUEST_JSON=$("$task_jq" -c --arg parent "${destination%/*}" '.storage={reserveBytes:8388608,paths:[{role:"restore-output",path:$parent,bytes:.backup.requiredBytes,inodes:0}]}' <<< "$TASK_REQUEST_JSON")
    task_storage_plan
    TASK_REQUEST_JSON=$saved
    task_backup_call revision show --revision "$revision"
    source_id=$("$task_jq" -r .result.sourceID <<< "$TASK_BACKUP_NATIVE")
    [ "$source_id" = "$("$task_jq" -r .sourceId <<< "$TASK_BACKUP_PLAN")" ] || task_stop blocked backup-scope-mismatch 0
    TASK_EFFECTS='["restore-new-directory"]'
    task_backup_call restore --revision "$revision" --directory --target-dir "$destination"
    TASK_BACKUP_RESTORED=$("$task_jq" -cn --arg destination "$destination" --arg revision "$revision" '{destination:$destination,revisionId:$revision,restored:true,applicationConsistencyVerified:false}')
}
