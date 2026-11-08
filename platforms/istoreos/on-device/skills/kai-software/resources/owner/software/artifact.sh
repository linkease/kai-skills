# Local reviewed build output; no inferred download URL or shell-evaluated recipe.
task_artifact_platform() {
    local os arch
    case "$(uname -s)" in Linux) os=linux ;; Darwin) os=macos ;; MINGW*|MSYS*|CYGWIN*) os=windows ;; *) return 2 ;; esac
    case "$(uname -m)" in x86_64|amd64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) return 2 ;; esac
    TASK_ARTIFACT_PLATFORM=$os-$arch
}
task_artifact_record() {
    local prefix=$1 marker=$2 command=$3 record=null
    [ ! -L "$prefix" ] && [ ! -L "$prefix/commands" ] && [ ! -L "$prefix/versions" ] && [ ! -L "$prefix/.managed" ] && [ ! -L "$prefix/current.json" ] && [ ! -L "$command" ] || task_stop blocked artifact-prefix-unowned 0
    if [ -e "$prefix" ];then
        [ -d "$prefix" ] && [ -f "$prefix/.managed" ] && [ "$(cat "$prefix/.managed")" = "$marker" ] || task_stop blocked artifact-prefix-unowned 0
        if [ -e "$prefix/current.json" ];then
            record=$("$task_jq" -c . < "$prefix/current.json") || task_stop blocked artifact-receipt-invalid 11
            "$task_jq" -e --arg software "$TASK_SOFTWARE" --arg target "$TASK_TARGET" --arg command "$command" '.application==$software and .targetId==$target and .command==$command and (.version|test("^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$")) and (.sha256|test("^[a-f0-9]{64}$")) and (.size|type=="number" and .>0)' <<< "$record" >/dev/null || task_stop blocked artifact-receipt-invalid 11
            [ -f "$command" ] && [ "$(task_digest "$command")" = "$("$task_jq" -r .sha256 <<< "$record")" ] || task_stop blocked artifact-command-modified 11
        elif [ -e "$command" ];then task_stop blocked artifact-command-unowned 0;fi
    elif [ -e "$command" ];then task_stop blocked artifact-command-unowned 0;fi
    TASK_ARTIFACT_RECORD=$record
}
task_artifact_plan() {
    local input intent base prefix command marker source sha size version platform body storage saved backup=null combined=null mode=${1:-artifact} url= source_commit=
    input=${2:-$(task_request_digest)};intent=$("$task_jq" -r '.intent//"install"' <<< "$TASK_REQUEST_JSON")
    case "$intent" in install|remove) ;; *) task_stop invalid invalid-intent 2 ;; esac
    task_artifact_platform || task_stop needs-ai artifact-platform-unrecognized 0
    base=$("$task_jq" -r '.prefixBase//""' <<< "$TASK_REQUEST_JSON");prefix=${base%/}/$TASK_SOFTWARE
    command=$prefix/commands/$TASK_SOFTWARE
    case "$TASK_ARTIFACT_PLATFORM" in windows-*) command=$command.exe ;; esac
    marker=software-artifact/v1:$TASK_TARGET:$TASK_SOFTWARE
    task_artifact_record "$prefix" "$marker" "$command"
    source=;sha=;size=65536;version=;source_commit=
    if [ "$intent" != remove ];then
        "$task_jq" -e '(.version|type=="string" and test("^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$")) and (.artifact|type=="object" and (.path|type=="string") and (.sha256|type=="string" and test("^[a-f0-9]{64}$")) and (.platform|type=="string") and (.verifyArgs|type=="array" and length<=32 and all(.[];type=="string" and length<=4096 and index("\u0000")==null)) and (.expectedOutput|type=="string" and length>0 and length<=4096))' <<< "$TASK_REQUEST_JSON" >/dev/null || task_stop invalid invalid-artifact-request 2
        [ "$("$task_jq" -r .artifact.platform <<< "$TASK_REQUEST_JSON")" = "$TASK_ARTIFACT_PLATFORM" ] || task_stop needs-ai artifact-platform-mismatch 0
        version=$("$task_jq" -r .version <<< "$TASK_REQUEST_JSON");source=$("$task_jq" -r .artifact.path <<< "$TASK_REQUEST_JSON");sha=$("$task_jq" -r .artifact.sha256 <<< "$TASK_REQUEST_JSON")
        if [ "$mode" = release ];then
            url=$("$task_jq" -r .artifact.url <<< "$TASK_REQUEST_JSON");size=$("$task_jq" .artifact.size <<< "$TASK_REQUEST_JSON");source_commit=$("$task_jq" -r .artifact.sourceCommit <<< "$TASK_REQUEST_JSON")
        else
            case "$source" in /*) ;; *) task_stop blocked unsafe-artifact-source 0 ;; esac
            [ -f "$source" ] && [ ! -L "$source" ] && [ "$(CDPATH= cd -- "$(dirname -- "$source")" && pwd -P)/$(basename -- "$source")" = "$source" ] || task_stop blocked unsafe-artifact-source 0
            size=$(wc -c < "$source");[ "$size" -gt 0 ] && [ "$size" -le 268435456 ] || task_stop needs-ai artifact-size-limit 0
            [ "$(task_digest "$source")" = "$sha" ] || task_stop blocked artifact-digest-mismatch 11
        fi
        if [ -e "$prefix/versions/$version" ];then
            [ ! -L "$prefix/versions" ] && [ ! -L "$prefix/versions/$version" ] && [ -f "$prefix/versions/$version/receipt.json" ] && [ ! -L "$prefix/versions/$version/receipt.json" ] && [ ! -L "$prefix/versions/$version/program" ] || task_stop blocked artifact-version-conflict 11
            if [ -e "$prefix/versions/$version/program" ];then [ -f "$prefix/versions/$version/program" ] && [ "$(task_digest "$prefix/versions/$version/program")" = "$sha" ] || task_stop blocked artifact-version-conflict 11;fi
            [ "$("$task_jq" -r .sha256 < "$prefix/versions/$version/receipt.json")" = "$sha" ] || task_stop blocked artifact-version-conflict 11
        fi
    fi
    TASK_REQUEST_JSON=$("$task_jq" -c --arg base "$base" --argjson size "$size" '.storage={reserveBytes:8388608,paths:[{role:"artifact-stage-immutable-version-and-command",path:$base,bytes:($size*4+65536),inodes:0}]}' <<< "$TASK_REQUEST_JSON")
    task_storage_plan;storage=$TASK_STORAGE_PLAN
    if [ "$intent" != remove ] && [ "$("$task_jq" -r '.backupRequired//false' <<< "$TASK_REQUEST_JSON")" = true ];then
        task_backup_plan;backup=$TASK_BACKUP_PLAN;saved=$TASK_REQUEST_JSON;task_backup_add_budget;task_storage_plan;combined=$TASK_STORAGE_PLAN;TASK_REQUEST_JSON=$saved
    fi
    body=$("$task_jq" -cn --arg method "$mode" --arg url "$url" --arg sourceCommit "$source_commit" --arg input "$input" --arg request "$(task_request_digest)" --arg owner "$(task_owner_digest)" --arg intent "$intent" --arg prefix "$prefix" --arg command "$command" --arg marker "$marker" --arg source "$source" --arg sha "$sha" --arg version "$version" --arg platform "$TASK_ARTIFACT_PLATFORM" --argjson size "$size" --argjson observed "$TASK_ARTIFACT_RECORD" --argjson storage "$storage" --argjson backup "$backup" --argjson combined "$combined" '{method:$method,url:$url,sourceCommit:$sourceCommit,intent:$intent,inputDigest:$input,requestDigest:$request,ownerDigest:$owner,prefix:$prefix,command:$command,marker:$marker,source:$source,sha256:$sha,size:$size,version:$version,platform:$platform,observed:$observed,storagePlan:$storage,backupPlan:$backup,combinedStoragePlan:$combined,effects:["managed-program-files","explicit-artifact-self-test"],executionPolicy:"foreground-owned-by-selected-target-transport"}')
    TASK_PLAN=$("$task_jq" -c --arg digest "$("$task_jq" -cS . <<< "$body" | task_hash_input)" '.+{planDigest:$digest}' <<< "$body")
}
task_artifact_cleanup() {
    if [ "${TASK_ARTIFACT_REPLACING:-0}" = 1 ] && [ "${TASK_ARTIFACT_COMMITTED:-0}" != 1 ];then
        if [ -f "$TASK_ARTIFACT_LOCK/old-command" ];then cp "$TASK_ARTIFACT_LOCK/old-command" "$TASK_ARTIFACT_COMMAND.candidate-recover" && mv -f "$TASK_ARTIFACT_COMMAND.candidate-recover" "$TASK_ARTIFACT_COMMAND" || return 1
        else rm -f "$TASK_ARTIFACT_COMMAND" || return 1;fi
    fi
    if [ "${TASK_ARTIFACT_COMMAND_STAGED:-0}" = 1 ];then rm -f "$TASK_ARTIFACT_COMMAND.candidate.$$";fi
    rm -f "$TASK_ARTIFACT_LOCK/candidate" "$TASK_ARTIFACT_LOCK/candidate.exe" "$TASK_ARTIFACT_LOCK/self-test.stdout" "$TASK_ARTIFACT_LOCK/old-command" "$TASK_ARTIFACT_LOCK/current.json"
    rmdir "$TASK_ARTIFACT_LOCK"
}
task_artifact_apply() {
    local expected=$1 prefix command marker source sha size version stage code=0 output arg receipt dir record stored files
    prefix=$("$task_jq" -r .prefix <<< "$expected");command=$("$task_jq" -r .command <<< "$expected");marker=$("$task_jq" -r .marker <<< "$expected")
    TASK_ARTIFACT_LOCK=$prefix.lock;TASK_ARTIFACT_COMMAND=$command;TASK_ARTIFACT_REPLACING=0;TASK_ARTIFACT_COMMITTED=0;TASK_ARTIFACT_COMMAND_STAGED=0
    (umask 077;mkdir "$TASK_ARTIFACT_LOCK") || task_stop blocked artifact-operation-in-progress 0
    trap 'task_artifact_cleanup' EXIT
    trap 'exit 130' INT;trap 'exit 143' TERM
    task_artifact_record "$prefix" "$marker" "$command"
    [ "$("$task_jq" -cS .observed <<< "$expected")" = "$("$task_jq" -cS . <<< "$TASK_ARTIFACT_RECORD")" ] || task_stop blocked artifact-state-changed 0
    task_storage_check "$("$task_jq" -c .storagePlan <<< "$expected")"
    if [ "$("$task_jq" -r .intent <<< "$expected")" = remove ];then
        if [ -d "$prefix/versions" ];then
            [ ! -L "$prefix/versions" ] || task_stop blocked artifact-version-unowned 0
            # Validate every owned version before deleting any program; foreign additions stay.
            for dir in "$prefix"/versions/*;do
                [ -e "$dir" ] || continue
                [ -d "$dir" ] && [ ! -L "$dir" ] && [ -f "$dir/receipt.json" ] && [ ! -L "$dir/receipt.json" ] && [ ! -L "$dir/program" ] || task_stop blocked artifact-version-unowned 0
                record=$("$task_jq" -c . < "$dir/receipt.json") || task_stop blocked artifact-receipt-invalid 11
                "$task_jq" -e --arg app "$TASK_SOFTWARE" --arg target "$TASK_TARGET" --arg version "${dir##*/}" '.application==$app and .targetId==$target and .version==$version' <<< "$record" >/dev/null || task_stop blocked artifact-receipt-invalid 11
                if [ -e "$dir/program" ];then [ -f "$dir/program" ] && [ "$(task_digest "$dir/program")" = "$("$task_jq" -r .sha256 <<< "$record")" ] || task_stop blocked artifact-version-modified 11;fi
            done
            TASK_EFFECTS='["managed-program-removal"]'
            for dir in "$prefix"/versions/*;do [ ! -d "$dir" ] || { rm -f "$dir/program" || task_stop failed artifact-remove-failed "$?";rmdir "$dir" 2>/dev/null || true; };done
        fi
        [ "$TASK_ARTIFACT_RECORD" = null ] || rm -f "$command" "$prefix/current.json" || task_stop failed artifact-remove-failed "$?"
        task_result success removed 0 '{"preserved":["configuration","data","foreign-files"]}' "${TASK_EFFECTS:-[]}";return
    fi
    source=$("$task_jq" -r .source <<< "$expected");sha=$("$task_jq" -r .sha256 <<< "$expected");size=$("$task_jq" .size <<< "$expected");version=$("$task_jq" -r .version <<< "$expected")
    stage=$TASK_ARTIFACT_LOCK/candidate;case "$TASK_ARTIFACT_PLATFORM" in windows-*) stage=$stage.exe ;; esac
    TASK_EFFECTS='["artifact-staging","explicit-artifact-self-test"]'
    TASK_ARTIFACT_PREPARATION=local-reviewed-artifact
    if [ "$("$task_jq" -r .method <<< "$expected")" = release ];then
        if [ -f "$prefix/versions/$version/program" ] && [ ! -L "$prefix/versions/$version/program" ] && [ "$(task_digest "$prefix/versions/$version/program")" = "$sha" ];then
            cp "$prefix/versions/$version/program" "$stage" || task_stop failed artifact-stage-failed "$?"
            TASK_ARTIFACT_PREPARATION=owned-version-cache
        elif [ -n "${KAI_RELEASE_ARTIFACT_CACHE:-}" ];then
            [ -f "$KAI_RELEASE_ARTIFACT_CACHE" ] && [ ! -L "$KAI_RELEASE_ARTIFACT_CACHE" ] && [ "$(wc -c < "$KAI_RELEASE_ARTIFACT_CACHE" | tr -d "[:space:]")" = "$size" ] && [ "$(task_digest "$KAI_RELEASE_ARTIFACT_CACHE")" = "$sha" ] || task_stop blocked release-cache-integrity 11
            cp "$KAI_RELEASE_ARTIFACT_CACHE" "$stage" || task_stop failed artifact-stage-failed "$?"
            TASK_ARTIFACT_PREPARATION=selected-verified-cache
        else
            local zsetup
            zsetup=${ZSETUP_BIN:-${KAI_ZSETUP_BIN:-$(type -P zsetup || true)}}
            [ -n "$zsetup" ] || { [ ! -x "$HOME/.local/bin/zsetup" ] || zsetup=$HOME/.local/bin/zsetup; }
            [ -n "$zsetup" ] && [ -x "$zsetup" ] || task_stop blocked missing-zsetup 127
            set -- "$zsetup" download -o "$stage" --sha256 "$sha" --size "$size"
            [ -z "${ZSETUP_CA_FILE:-}" ] || set -- "$@" --ca-file "$ZSETUP_CA_FILE"
            TASK_EFFECTS='["verified-release-download-attempt","artifact-staging"]'
            "$@" "$("$task_jq" -r .url <<< "$expected")" >&2 || task_stop failed release-download-failed "$?"
            TASK_ARTIFACT_PREPARATION=native-zsetup
        fi
    else cp "$source" "$stage" || task_stop failed artifact-stage-failed "$?";fi
    chmod 755 "$stage" || task_stop failed artifact-stage-failed "$?"
    [ "$(task_digest "$stage")" = "$sha" ] || task_stop blocked artifact-digest-mismatch 11
    local argv=();while IFS= read -r -d '' arg;do argv+=("$arg");done < <("$task_jq" -j '.artifact.verifyArgs[]|.+"\u0000"' <<< "$TASK_REQUEST_JSON")
    "$stage" "${argv[@]}" | head -c 65536 > "$TASK_ARTIFACT_LOCK/self-test.stdout" || code=$?
    [ "$code" = 0 ] || task_stop failed artifact-functional-check-failed "$code"
    [ "$(wc -c < "$TASK_ARTIFACT_LOCK/self-test.stdout")" -lt 65536 ] || task_stop failed artifact-output-limit 11
    output=$(cat "$TASK_ARTIFACT_LOCK/self-test.stdout")
    [[ "$output" == *"$("$task_jq" -r .artifact.expectedOutput <<< "$TASK_REQUEST_JSON")"* ]] || task_stop failed artifact-functional-check-failed 11
    if [ "$TASK_ARTIFACT_RECORD" != null ] && [ "$("$task_jq" -r .sha256 <<< "$TASK_ARTIFACT_RECORD")" = "$sha" ] && [ "$("$task_jq" -r .version <<< "$TASK_ARTIFACT_RECORD")" = "$version" ];then
        task_result success reused 0 "$("$task_jq" -cn --arg command "$command" --arg preparation "$TASK_ARTIFACT_PREPARATION" '{command:$command,functionalValidation:"passed",preparation:$preparation}')" "$TASK_EFFECTS";return
    fi
    if [ ! -e "$prefix" ];then (umask 077;mkdir "$prefix" && printf '%s\n' "$marker" > "$prefix/.managed") || task_stop failed artifact-prefix-create-failed "$?";fi
    [ ! -L "$prefix/versions" ] && [ ! -L "$prefix/commands" ] || task_stop blocked artifact-prefix-unowned 0
    mkdir -p "$prefix/versions/$version" "$prefix/commands" || task_stop failed artifact-directory-create-failed "$?"
    receipt=$("$task_jq" -cn --argjson plan "$expected" --argjson request "$TASK_REQUEST_JSON" --arg preparation "$TASK_ARTIFACT_PREPARATION" --arg app "$TASK_SOFTWARE" --arg target "$TASK_TARGET" --arg version "$version" --arg sha "$sha" --argjson size "$size" --arg command "$command" '{application:$app,targetId:$target,version:$version,sha256:$sha,size:$size,command:$command,platform:$plan.platform,verifiedFeatures:($request.features//[]),verification:{args:$request.artifact.verifyArgs,expectedOutput:$request.artifact.expectedOutput},functionalValidation:"passed",provenance:{method:$plan.method,sourceCommit:$plan.sourceCommit,url:$plan.url,planDigest:$plan.planDigest,preparation:$preparation}}')
    if [ ! -e "$prefix/versions/$version/program" ];then
        cp "$stage" "$prefix/versions/$version/program" && chmod 755 "$prefix/versions/$version/program" && printf '%s\n' "$receipt" > "$prefix/versions/$version/receipt.json" || task_stop failed artifact-version-write-failed "$?"
    fi
    [ ! -e "$command" ] || cp "$command" "$TASK_ARTIFACT_LOCK/old-command" || task_stop failed artifact-command-backup-failed "$?"
    [ ! -e "$command.candidate.$$" ] && [ ! -L "$command.candidate.$$" ] || task_stop blocked artifact-command-stage-conflict 0
    (set -C; : > "$command.candidate.$$") || task_stop failed artifact-command-stage-failed "$?"
    TASK_ARTIFACT_COMMAND_STAGED=1
    cat "$stage" > "$command.candidate.$$" && chmod 755 "$command.candidate.$$" || task_stop failed artifact-command-stage-failed "$?"
    TASK_ARTIFACT_REPLACING=1
    mv -f "$command.candidate.$$" "$command" || task_stop failed artifact-activation-failed "$?"
    printf '%s\n' "$receipt" > "$TASK_ARTIFACT_LOCK/current.json" && mv -f "$TASK_ARTIFACT_LOCK/current.json" "$prefix/current.json" || task_stop failed artifact-receipt-commit-failed "$?"
    TASK_ARTIFACT_COMMITTED=1
    task_result success installed 0 "$("$task_jq" -cn --arg preparation "$TASK_ARTIFACT_PREPARATION" --arg command "$command" --arg sha "$sha" '{command:$command,sha256:$sha,functionalValidation:"passed",preparation:$preparation}')" '["managed-program-files"]'
}

task_artifact_query() {
    local base prefix command marker record wanted version_match=false features_match=false status=not-run arg output code=0
    task_artifact_platform || task_stop needs-ai artifact-platform-unrecognized 0
    base=$("$task_jq" -r '.prefixBase//""' <<< "$TASK_REQUEST_JSON")
    case "$base" in /*) ;; *) task_stop blocked unsafe-artifact-prefix 0 ;; esac
    [ -d "$base" ] && [ ! -L "$base" ] && [ "$(CDPATH= cd -- "$base" && pwd -P)" = "$base" ] || task_stop blocked unsafe-artifact-prefix 0
    prefix=${base%/}/$TASK_SOFTWARE;command=$prefix/commands/$TASK_SOFTWARE
    case "$TASK_ARTIFACT_PLATFORM" in windows-*) command=$command.exe ;; esac
    marker=software-artifact/v1:$TASK_TARGET:$TASK_SOFTWARE
    task_artifact_record "$prefix" "$marker" "$command";record=$TASK_ARTIFACT_RECORD
    if [ "$record" = null ];then
        [ "$TASK_OPERATION" != verify ] || task_stop failed artifact-not-installed 11
        TASK_OBSERVED='{"installed":false,"functionalValidation":"not-run"}';return
    fi
    wanted=$("$task_jq" -r '.version//""' <<< "$TASK_REQUEST_JSON")
    if [ -z "$wanted" ] || [ "$wanted" = "$("$task_jq" -r .version <<< "$record")" ];then version_match=true;fi
    if "$task_jq" -e --argjson record "$record" '(.features//[])|all(.[];. as $f|($record.verifiedFeatures//[])|index($f)!=null)' <<< "$TASK_REQUEST_JSON" >/dev/null;then features_match=true;fi
    if [ "$TASK_OPERATION" = verify ];then
        [ "$version_match" = true ] || task_stop failed artifact-installed-version-mismatch 11
        [ "$features_match" = true ] || task_stop needs-ai unknown-functional-requirement 0
        [ "$("$task_jq" -r '.platform//""' <<< "$record")" = "$TASK_ARTIFACT_PLATFORM" ] || task_stop needs-ai stored-platform-identity-required 0
        "$task_jq" -e '.verification|type=="object" and (.args|type=="array" and length<=32 and all(.[];type=="string" and length<=4096 and index("\u0000")==null)) and (.expectedOutput|type=="string" and length>0 and length<=4096)' <<< "$record" >/dev/null || task_stop needs-ai stored-functional-check-required 0
        local argv=();while IFS= read -r -d '' arg;do argv+=("$arg");done < <("$task_jq" -j '.verification.args[]|.+"\u0000"' <<< "$record")
        TASK_EFFECTS='["explicit-artifact-self-test"]'
        output=$("$command" "${argv[@]}" | head -c 65536) || code=$?
        [ "$code" = 0 ] || task_stop failed artifact-functional-check-failed "$code"
        [ "${#output}" -lt 65536 ] && [[ "$output" == *"$("$task_jq" -r .verification.expectedOutput <<< "$record")"* ]] || task_stop failed artifact-functional-check-failed 11
        status=passed
    fi
    TASK_OBSERVED=$("$task_jq" -c --arg status "$status" --argjson matches "$version_match" '.+{installed:true,satisfiesVersion:$matches,functionalValidation:$status}' <<< "$record")
}
