#!/usr/bin/env bash
set -u
set -o pipefail
project_here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_entry=${KAI_SOFTWARE_TASK_ENTRY:-$project_here/../../kai-software/resources/owner/software/task.sh}
task_root=$(CDPATH= cd -- "$(dirname -- "$project_entry")" && pwd) || exit 21
. "$task_root/protocol.sh"
case "$TASK_OPERATION" in project-plan|project-apply) ;; *) task_stop invalid unknown-operation 2 ;; esac
task_request "${2:-}"
. "$task_root/storage.sh"
. "$task_root/selection.sh"
project_runtime=${KAI_PROJECT_RUNTIME_ENTRY:-$project_here/../../kai-dev-environment/scripts/runtime.sh}
project_dependencies=${KAI_PROJECT_DEPENDENCY_ENTRY:-$project_here/../../kai-project-dependencies/scripts/dependencies.sh}
project_owner_digest() {
    { task_owner_digest;task_digest "$project_here/project.sh";task_digest "$project_runtime";task_digest "$project_dependencies";task_digest "$project_here/../resources/sdk-openssl.cnf"; } | task_hash_input
}
project_source() {
    local path=$1 directory physical size digest
    case "$path" in ''|/*|*../*|../*|*/..|*//*|./*|*/./*) task_stop blocked unsafe-project-source 0 ;; esac
    [ -f "$PROJECT_PATH/$path" ] && [ ! -L "$PROJECT_PATH/$path" ] || task_stop blocked unsafe-project-source 0
    directory=$(dirname -- "$PROJECT_PATH/$path");physical=$(CDPATH= cd -- "$directory" && pwd -P)
    [ "$directory" = "$physical" ] || task_stop blocked unsafe-project-source 0
    size=$(wc -c < "$PROJECT_PATH/$path");[ "$size" -le 1048576 ] || task_stop needs-ai project-source-plan-limit 0
    digest=$(task_digest "$PROJECT_PATH/$path") || task_stop blocked missing-sha256 127
    PROJECT_FILES=$("$task_jq" -cn --argjson previous "$PROJECT_FILES" --arg file "$path" --arg sha "$digest" '$previous+[{path:$file,sha256:$sha}]')
}
project_make_plan() {
    local input kind version manager entry run build probe code budget file body count=0 work owner physical
    input=$(task_request_digest)
    "$task_jq" -e '.project|type=="object" and (.path|type=="string") and (.runtimeVersion|type=="string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and (.sourceFiles|type=="array" and length>0 and length<=128 and all(.[];type=="string")) and (.expectedOutput|type=="string" and length>0 and length<=4096) and (.budgetBytes|type=="number" and floor==. and .>=1048576 and .<=1000000000000)' <<< "$TASK_REQUEST_JSON" >/dev/null || task_stop invalid invalid-project-request 2
    PROJECT_PATH=$("$task_jq" -r .project.path <<< "$TASK_REQUEST_JSON")
    [ -d "$PROJECT_PATH" ] && [ ! -L "$PROJECT_PATH" ] || task_stop blocked unsafe-project-directory 0
    physical=$(CDPATH= cd -- "$PROJECT_PATH" && pwd -P);[ "$PROJECT_PATH" = "$physical" ] || task_stop blocked unsafe-project-directory 0
    kind=$("$task_jq" -r '.project.kind//""' <<< "$TASK_REQUEST_JSON")
    if [ -z "$kind" ]; then
        if [ -f "$PROJECT_PATH/package.json" ];then kind=node;count=$((count+1));fi
        if [ -f "$PROJECT_PATH/requirements.txt" ];then kind=python;count=$((count+1));fi
        if [ -f "$PROJECT_PATH/go.mod" ];then kind=go;count=$((count+1));fi
        [ "$count" -le 1 ] || task_stop needs-ai ambiguous-project-kind 0 '{"attempted":["manifest-detection"],"required":["choose-project-kind"]}'
    fi
    PROJECT_CRYPTO_POLICY=$("$task_jq" -r '.project.cryptoPolicy//"inherit-target"' <<< "$TASK_REQUEST_JSON")
    case "$PROJECT_CRYPTO_POLICY" in inherit-target|sdk-default) ;; *) task_stop needs-ai unknown-project-crypto-policy 0 ;; esac
    PROJECT_FILES='[]';entry=;run=;build=
    case "$kind" in
      node)
        manager=npm;project_source package.json
        [ -f "$PROJECT_PATH/package-lock.json" ] || task_stop needs-ai project-lock-required 0 '{"attempted":["manifest-detection","npm-lock"],"required":["review-existing-package-manager-and-lock"]}'
        project_source package-lock.json
        "$task_jq" -e '(.packageManager//"npm")|test("^npm(@.*)?$")' < "$PROJECT_PATH/package.json" >/dev/null || task_stop needs-ai project-package-manager-required 0
        run=$("$task_jq" -r '.project.runScript//"start"' <<< "$TASK_REQUEST_JSON");build=$("$task_jq" -r '.project.buildScript//""' <<< "$TASK_REQUEST_JSON")
        "$task_jq" -e --arg run "$run" --arg build "$build" '(.scripts[$run]|type=="string") and ($build=="" or (.scripts[$build]|type=="string"))' < "$PROJECT_PATH/package.json" >/dev/null || task_stop needs-ai project-run-script-required 0 ;;
      python)
        manager=pip;project_source requirements.txt
        entry=$("$task_jq" -r '.project.entry//""' <<< "$TASK_REQUEST_JSON");project_source "$entry" ;;
      go)
        manager=go;project_source go.mod
        [ ! -f "$PROJECT_PATH/go.sum" ] || project_source go.sum ;;
      *) task_stop needs-ai project-recipe-required 0 '{"attempted":["manifest-detection"],"required":["project-kind","selected-sdk","locked-dependencies","build-and-run-recipe"]}' ;;
    esac
    while IFS= read -r file; do project_source "$file";done < <("$task_jq" -r '.project.sourceFiles[]' <<< "$TASK_REQUEST_JSON")
    PROJECT_FILES=$("$task_jq" -c 'unique_by(.path)' <<< "$PROJECT_FILES")
    version=$("$task_jq" -r .project.runtimeVersion <<< "$TASK_REQUEST_JSON")
    probe=$(bash "$project_runtime" probe "$kind" "$version");code=$?
    [ "$code" = 0 ] || task_stop blocked project-sdk-preparation-required "$code" "$("$task_jq" -cn --argjson probe "${probe:-null}" '{sdkProbe:$probe,required:["prepare-selected-sdk"]}')"
    "$task_jq" -e '.status=="passed" and (.installRoot|type=="string" and length>0)' <<< "$probe" >/dev/null || task_stop failed invalid-project-sdk-probe 11
    work=$PROJECT_PATH/.kai-project;owner=$(printf '%s\n%s\n' "$TASK_TARGET" "$PROJECT_PATH" | task_hash_input)
    [ ! -L "$work" ] || task_stop blocked project-workspace-unowned 0
    if [ -e "$work" ];then [ -f "$work/.managed" ] && [ ! -L "$work/.managed" ] && [ "$(cat "$work/.managed")" = "$owner" ] || task_stop blocked project-workspace-unowned 0;fi
    budget=$("$task_jq" .project.budgetBytes <<< "$TASK_REQUEST_JSON")
    TASK_REQUEST_JSON=$("$task_jq" -c --arg path "$PROJECT_PATH" --argjson bytes "$budget" '.storage={reserveBytes:8388608,paths:[{role:"project-dependencies-cache-build-output",path:$path,bytes:$bytes,inodes:0}]}' <<< "$TASK_REQUEST_JSON")
    task_storage_plan
    body=$("$task_jq" -cn --arg input "$input" --arg request "$(task_request_digest)" --arg owner "$(project_owner_digest)" --arg kind "$kind" --arg manager "$manager" --arg path "$PROJECT_PATH" --arg work "$work" --arg workOwner "$owner" --arg entry "$entry" --arg run "$run" --arg build "$build" --arg version "$version" --arg crypto "$PROJECT_CRYPTO_POLICY" --arg cryptoSHA "$(task_digest "$project_here/../resources/sdk-openssl.cnf")" --argjson sdk "$probe" --argjson files "$PROJECT_FILES" --argjson storage "$TASK_STORAGE_PLAN" '{inputDigest:$input,requestDigest:$request,ownerDigest:$owner,kind:$kind,manager:$manager,path:$path,workDir:$work,workOwner:$workOwner,entry:$entry,runScript:$run,buildScript:$build,cryptoPolicy:$crypto,cryptoConfigSHA256:$cryptoSHA,runtime:{name:$kind,version:$version,installRoot:$sdk.installRoot},files:$files,storagePlan:$storage,budgetKind:"preflight-reservation",lockPolicy:"native-lock-preserved; pip-require-hashes",effects:["project-native-dependencies","project-owned-cache-and-output","execute-reviewed-project"],executionPolicy:"foreground-owned-by-selected-target-transport"}')
    PROJECT_PLAN=$("$task_jq" -c --arg digest "$("$task_jq" -cS . <<< "$body" | task_hash_input)" '.+{planDigest:$digest}' <<< "$body")
}
project_execute() {
    local kind=$1 version=$2 path=$3 work=$4 run=$5 entry=$6 build=$7
    if [ "$kind:$PROJECT_CRYPTO_POLICY" = python:sdk-default ];then
        local config=$work/openssl.cnf config_sha
        config_sha=$(task_digest "$project_here/../resources/sdk-openssl.cnf")
        [ ! -L "$config" ] || return 11
        if [ -e "$config" ];then [ -f "$config" ] && [ "$(task_digest "$config")" = "$config_sha" ] || return 11
        else cp "$project_here/../resources/sdk-openssl.cnf" "$config" || return $?;fi
        export OPENSSL_CONF=$config
    fi
    bash "$project_runtime" verify "$kind" "$version" >&2 || return $?
    bash "$project_dependencies" install "$PROJECT_MANAGER" "$version" "$path" >&2 || return $?
    case "$kind" in
      node)
        if [ -n "$build" ];then bash "$project_dependencies" run npm "$version" "$path" -- run "$build" >&2 || return $?;fi
        bash "$project_dependencies" run npm "$version" "$path" -- run "$run" ;;
      python)
        local python=$path/.venv/bin/python
        [ ! -x "$path/.venv/Scripts/python.exe" ] || python=$path/.venv/Scripts/python.exe
        (cd -- "$path" && bash "$project_runtime" exec python "$version" -- "$python" "$entry") ;;
      go)
        local binary=$work/project-program
        case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) binary=$binary.exe ;; esac
        bash "$project_dependencies" run go "$version" "$path" -- build -o "$binary" . >&2 || return $?
        "$binary" ;;
    esac
}
if [ "$TASK_OPERATION" = project-plan ];then project_make_plan;task_result success project-planned 0 "$PROJECT_PLAN";exit 0;fi
expected=$("$task_jq" -c '.plan//null' <<< "$TASK_REQUEST_JSON")
[ "$expected" != null ] || task_stop blocked missing-plan 0
[ "$("$task_jq" -r .inputDigest <<< "$expected")" = "$(task_request_digest)" ] || task_stop blocked project-plan-changed 0
[ "$("$task_jq" -cS 'del(.planDigest)' <<< "$expected" | task_hash_input)" = "$("$task_jq" -r .planDigest <<< "$expected")" ] || task_stop blocked project-plan-changed 0
project_make_plan
[ "$("$task_jq" -cS 'del(.storagePlan,.planDigest)' <<< "$expected")" = "$("$task_jq" -cS 'del(.storagePlan,.planDigest)' <<< "$PROJECT_PLAN")" ] || task_stop blocked project-plan-changed 0
task_storage_check "$("$task_jq" -c .storagePlan <<< "$expected")"
work=$("$task_jq" -r .workDir <<< "$expected");TASK_PROJECT_LOCK=$work.lock
(umask 077;mkdir "$TASK_PROJECT_LOCK") || task_stop blocked project-operation-in-progress 0
trap 'rmdir "$TASK_PROJECT_LOCK" 2>/dev/null || true' EXIT
if [ ! -e "$work" ];then (umask 077;mkdir "$work" && printf '%s\n' "$("$task_jq" -r .workOwner <<< "$expected")" > "$work/.managed") || task_stop failed project-workspace-create-failed "$?";fi
for directory in cache cache/npm cache/pip cache/go-mod cache/go-build cache/go;do
    [ ! -L "$work/$directory" ] || task_stop blocked unsafe-project-workspace 0
    mkdir -p "$work/$directory" || task_stop failed project-cache-create-failed "$?"
done
export npm_config_cache=$work/cache/npm PIP_CACHE_DIR=$work/cache/pip GOMODCACHE=$work/cache/go-mod GOCACHE=$work/cache/go-build GOPATH=$work/cache/go GOTOOLCHAIN=local PIP_REQUIRE_HASHES=1
TASK_EFFECTS='["project-native-dependencies","project-owned-cache-and-output","execute-reviewed-project"]'
PROJECT_MANAGER=$("$task_jq" -r .manager <<< "$expected")
code=0
project_execute "$("$task_jq" -r .kind <<< "$expected")" "$("$task_jq" -r .runtime.version <<< "$expected")" "$PROJECT_PATH" "$work" "$("$task_jq" -r .runScript <<< "$expected")" "$("$task_jq" -r .entry <<< "$expected")" "$("$task_jq" -r .buildScript <<< "$expected")" | head -c 65536 > "$work/run.stdout" || code=$?
[ "$code" = 0 ] || task_stop failed project-native-execution-failed "$code"
[ "$(wc -c < "$work/run.stdout")" -lt 65536 ] || task_stop failed project-output-limit 11
output=$(cat "$work/run.stdout");expected_output=$("$task_jq" -r .project.expectedOutput <<< "$TASK_REQUEST_JSON")
[[ "$output" == *"$expected_output"* ]] || task_stop failed project-functional-verification-failed 11
while IFS= read -r file;do
    old=$("$task_jq" -r --arg path "$file" '.files[]|select(.path==$path)|.sha256' <<< "$expected")
    [ "$(task_digest "$PROJECT_PATH/$file")" = "$old" ] || task_stop failed project-source-or-lock-drift 11
done < <("$task_jq" -r '.files[].path' <<< "$expected")
project_artifact=$work/project-program;case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) project_artifact=$project_artifact.exe ;; esac
details=$("$task_jq" -cn --arg artifact "$project_artifact" --argjson plan "$expected" --arg output "$output" '{kind:$plan.kind,runtime:$plan.runtime,workDir:$plan.workDir,sourceAndLocksPreserved:true,functionalValidation:"passed",output:$output,artifact:(if $plan.kind=="go" then {state:"built-not-installed",path:$artifact} else null end)}')
task_result success project-ran 0 "$details" "$TASK_EFFECTS"
