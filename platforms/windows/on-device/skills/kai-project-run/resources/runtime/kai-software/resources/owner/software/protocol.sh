# Shared machine result contract. This module never installs or starts programs.
task_jq=${ZSETUP_TASK_JQ:-$(command -v jq 2>/dev/null || true)}
if [ -z "$task_jq" ] && [ -x "$HOME/.local/bin/jq" ]; then task_jq=$HOME/.local/bin/jq; fi
if [ -z "$task_jq" ] || ! "$task_jq" -ne '"abc"|test("^a")' >/dev/null 2>&1; then
    printf '%s\n' '{"protocol":"software-task/v1","schemaVersion":1,"operation":null,"targetId":null,"software":null,"status":"blocked","reason":"missing-full-jq","nativeExitCode":127,"effects":[],"details":{}}'
    exit 21
fi
task_jq_binary=$task_jq
task_jq_native_windows=0
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) task_jq_native_windows=1 ;; esac
task_json() {
    # Native jq must receive JSON string arguments literally. MSYS otherwise
    # rewrites --arg /d/path into a Windows path inside the JSON document.
    if [ "$task_jq_native_windows" = 1 ];then
        MSYS2_ARG_CONV_EXCL='*' "$task_jq_binary" --binary "$@"
    else MSYS2_ARG_CONV_EXCL='*' "$task_jq_binary" "$@";fi
}
task_jq=task_json
TASK_OPERATION=${1:-}; TASK_SOFTWARE=; TASK_TARGET=${ZSETUP_TASK_TARGET_ID:-local}
task_result() {
    "$task_jq" -cn --arg operation "$TASK_OPERATION" --arg target "$TASK_TARGET" \
        --arg software "$TASK_SOFTWARE" --arg status "$1" --arg reason "$2" \
        --argjson native "$3" --argjson details "${4:-\{\}}" --argjson effects "${5:-[]}" \
        '{protocol:"software-task/v1",schemaVersion:1,operation:$operation,targetId:$target,software:$software,status:$status,reason:$reason,nativeExitCode:$native,effects:$effects,details:$details}'
}
task_stop() {
    task_status=$1; task_reason=$2; task_native=$3; task_details=${4:-\{\}}
    task_result "$task_status" "$task_reason" "$task_native" "$task_details" "${5:-${TASK_EFFECTS:-[]}}"
    case "$task_status" in needs-ai) exit 20 ;; blocked) exit 21 ;; failed) exit 22 ;; *) exit 2 ;; esac
}
task_request() {
    TASK_REQUEST=${1:-}
    [ -f "$TASK_REQUEST" ] && [ ! -L "$TASK_REQUEST" ] || task_stop invalid invalid-request-file 2
    [ "$(wc -c < "$TASK_REQUEST")" -le 65536 ] || task_stop invalid request-too-large 2
    "$task_jq" -e 'type=="object" and (.software|type=="string" and test("^[a-zA-Z0-9][a-zA-Z0-9._+-]{0,127}$")) and (.targetId|type=="string" and test("^[a-zA-Z0-9][a-zA-Z0-9._:+-]{0,127}$")) and ((.version//"")|type=="string" and length<=128) and ((.features//[])|type=="array" and all(.[];type=="string"))' < "$TASK_REQUEST" >/dev/null 2>&1 || task_stop invalid invalid-request 2
    TASK_SOFTWARE=$("$task_jq" -r .software < "$TASK_REQUEST")
    TASK_REQUEST_JSON=$(cat "$TASK_REQUEST")
    task_expected=$("$task_jq" -r .targetId < "$TASK_REQUEST")
    [ "$task_expected" = "$TASK_TARGET" ] || task_stop blocked target-mismatch 0
}
task_digest() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d ' ' -f 1
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d ' ' -f 1
    else return 127; fi
}
task_hash_input() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d ' ' -f 1
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d ' ' -f 1
    else return 127; fi
}
task_request_digest() {
    "$task_jq" -cS 'del(.storagePlan,.plan)' <<< "$TASK_REQUEST_JSON" | task_hash_input
}
