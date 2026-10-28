#!/usr/bin/env bash
set -eu
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
. "$here/../../kai-tool-bootstrap/scripts/jq-env.sh"
kai_use_jq full || exit $?
fail() { jq -cn --argjson code "$1" --arg category "$2" --arg reason "$3" '{schemaVersion:1,status:"failed",category:$category,reason:$reason,exitCode:$code}'; exit "$1"; }
platform="${KAI_PLATFORM:-$(bash "$here/../../kai-tool-bootstrap/scripts/tool.sh" probe bash | jq -er .platform)}"
action="${1:-}"
if [ "$action" = cli ]; then shift; exec bash "$here/../../kai-dev-environment/scripts/dev-cli.sh" "$@"; fi
case "$action" in space|search|storage) ;; *) fail 2 usage 'usage.sh space ROOT [LIMIT [SECONDS]] | search ROOT TERM [LIMIT [SECONDS]] | storage ROOT [MIN_FREE_BYTES] | cli ...' ;; esac
root="${2:-}"; case "$root" in /*) ;; *) fail 2 scope 'an explicit absolute directory is required' ;; esac
[ -d "$root" ] && [ ! -L "$root" ] || fail 2 scope 'use an existing directory rather than creating or following a root link'
root="$(CDPATH= cd -- "$root" && pwd -P)"
if [ "$action" != storage ]; then [ "$root" != / ] || fail 2 scope 'select a bounded subdirectory; whole-root scans are not a default query'; fi
python_command() {
    python="${KAI_USAGE_PYTHON:-}"
    [ -n "$python" ] && [ -x "$python" ] || fail 127 missing-executable 'the native fallback needs an existing Python 3; supply its selected path with KAI_USAGE_PYTHON'
    native_script="$here/native.py"; native_root="$root"
    if [ "$platform" = windows ]; then
        native_script="$(cygpath -w "$native_script")"; native_root="$(cygpath -w "$root")"
    fi
}
if [ "$action" = storage ]; then
    minimum="${3:-1048576}"
    [[ "$minimum" =~ ^(0|[1-9][0-9]{0,14})$ ]] || fail 2 usage 'minimum free bytes must be a bounded nonnegative integer'
    code=0
    case "$platform" in
        ubuntu|debian|linux|istoreos|openwrt)
            core="${KAI_ZSETUP_BIN:-$(command -v zsetup 2>/dev/null || true)}"
            [ -n "$core" ] || { [ ! -x "$HOME/.local/bin/zsetup" ] || core="$HOME/.local/bin/zsetup"; }
            [ -n "$core" ] && [ -x "$core" ] || fail 127 missing-executable 'read-only storage facts need an existing zsetup >=0.5'
            facts="$("$core" storage "$root" --json)" || code=$?; tool=zsetup-storage ;;
        macos|windows)
            python_command
            if [ "$platform" = windows ]; then
                facts="$(MSYS2_ARG_CONV_EXCL='*' PYTHONIOENCODING=utf-8 "$python" "$native_script" storage "$native_root")" || code=$?
            else facts="$("$python" "$native_script" storage "$native_root")" || code=$?; fi
            tool=python-native-storage ;;
        *) fail 18 unsupported-platform 'no storage facts adapter for this target' ;;
    esac
    [ "$code" = 0 ] || { [ -z "$facts" ] || printf '%s\n' "$facts" >&2; fail "$code" storage-query-failed 'native storage query failed; no files were created'; }
    printf '%s' "$facts" | jq -e '.schema_version==1 and has("memory_backed") and has("filesystem_type") and (.available_bytes|type)=="number"' >/dev/null || fail 4 facts-unavailable 'native storage facts are incomplete or unknown'
    printf '%s' "$facts" | jq --arg root "$root" --arg tool "$tool" --argjson minimum "$minimum" '
      . as $f | ((.filesystem_type//"")|ascii_downcase) as $fs |
      (if (["overlay","overlayfs","aufs"]|index($fs))!=null then "container-layer"
       elif .memory_backed==true then "temporary"
       elif .memory_backed==false and (["ext2","ext3","ext4","xfs","btrfs","zfs","f2fs","ubifs","apfs","hfs","hfsplus","ntfs","refs","exfat","msdos","vfat"]|index($fs))!=null then "persistent"
       else "unknown" end) as $p |
      {schemaVersion:1,status:"passed",operation:"storage",tool:$tool,path:$root,facts:$f,persistence:$p,
       eligibleForInstall:($p=="persistent" and .read_only==false and .noexec==false and .writable==true and .available_bytes >= $minimum),
       minimumFreeBytes:$minimum,nextStep:(if $p=="persistent" then "verify the intended directory and budget before installation" else "choose storage with verified persistent backing" end),exitCode:0}'
    exit 0
fi
term=''
if [ "$action" = search ]; then term="${3:-}"; [ -n "$term" ] || fail 2 usage 'search needs a literal filename term'; limit="${4:-20}"; seconds="${5:-30}"
else limit="${3:-20}"; seconds="${4:-30}"; fi
[[ "$limit" =~ ^[1-9][0-9]{0,3}$ ]] && [ "$limit" -le 1000 ] || fail 2 bounds 'query limit must be 1..1000'
[[ "$seconds" =~ ^[1-9][0-9]{0,2}$ ]] && [ "$seconds" -le 300 ] || fail 2 bounds 'query timeout must be 1..300 seconds'
backend="${KAI_USAGE_BACKEND:-auto}"
if [ "$backend" = auto ]; then
    case "$platform" in
        ubuntu|debian|linux|istoreos|openwrt)
            case "${KAI_TARGET_ARCH:-$(uname -m)}" in x64|x86_64|amd64|arm64|aarch64|armv7|armv7l) backend=linkspace ;; *) backend=native ;; esac ;;
        macos|windows) backend=native ;;
        *) fail 18 unsupported-platform 'no filesystem usage adapter for this target' ;;
    esac
fi
case "$backend" in
    linkspace)
        program="${KAI_LINKSPACE_BIN:-$(command -v linkspace 2>/dev/null || true)}"
        [ -n "$program" ] || { [ ! -x "$HOME/.local/bin/linkspace" ] || program="$HOME/.local/bin/linkspace"; }
        [ -n "$program" ] && [ -x "$program" ] || fail 127 missing-executable 'install or select the published Linkspace client before scanning'
        identity="$("$program" version)" || fail 4 tool-incompatible 'Linkspace did not report its CLI version'
        printf '%s' "$identity" | jq -e '.schemaVersion==1 and (.version|type)=="string"' >/dev/null || fail 4 tool-incompatible 'unsupported Linkspace output contract'
        scratch="${KAI_USAGE_TEMP_DIR:-${TMPDIR:-/tmp}}"
        [ -d "$scratch" ] && [ -w "$scratch" ] || fail 2 temporary-directory 'choose an existing writable temporary directory outside the scan root'
        scratch="$(CDPATH= cd -- "$scratch" && pwd -P)"
        case "$scratch/" in "$root/"*) fail 2 temporary-directory 'temporary files must stay outside the scanned directory' ;; esac
        if [ "$action" = space ]; then
            command=("$program" space top --path "$root" --source scan --scope filesystem --metric allocated --limit "$limit" --temp-dir "$scratch" --max-temp-bytes 64MiB)
        else command=("$program" query --mode contains --path "$root" --source scan --limit "$limit" --temp-dir "$scratch"); fi
        command+=(--timeout "${seconds}s" --non-interactive --json)
        [ "$action" != search ] || command+=(-- "$term")
        tool=linkspace ;;
    native)
        python_command
        entries="${KAI_USAGE_MAX_ENTRIES:-10000}"
        [[ "$entries" =~ ^[1-9][0-9]{0,6}$ ]] && [ "$entries" -le 1000000 ] || fail 2 bounds 'native entry budget must be 1..1000000'
        command=("$python" "$native_script" "$action" "$native_root" --limit "$limit" --timeout "$seconds" --max-entries "$entries")
        [ "$action" != search ] || command+=("--term=$term")
        tool=python-stdlib; program="$python" ;;
    *) fail 2 usage 'backend must be auto, linkspace or native' ;;
esac
code=0
if [ "$backend:$platform" = native:windows ]; then
    output="$(MSYS2_ARG_CONV_EXCL='*' PYTHONIOENCODING=utf-8 "${command[@]}")" || code=$?
else output="$("${command[@]}")" || code=$?; fi
native="$(printf '%s' "$output" | jq -ce . 2>/dev/null)" || native=null
if [ "$code" = 0 ] && ! printf '%s' "$native" | jq -e '.schemaVersion==1 and .status=="succeeded" and (.result|type)=="object" and (.result.root|type)=="string"' >/dev/null; then
    [ -z "$output" ] || printf '%s\n' "$output" >&2
    fail 4 result-unavailable 'the native query returned no compatible scoped result'
fi
argv="$(printf '%s\0' "${command[@]}" | jq -Rs 'split("\u0000")[:-1]')"
status=failed; [ "$code" != 0 ] || status=passed; [ "$code" != 11 ] || status=partial
jq -cn --arg action "$action" --arg root "$root" --arg tool "$tool" --arg executable "$program" --arg status "$status" \
    --argjson code "$code" --argjson native "$native" --argjson argv "$argv" \
    '{schemaVersion:1,status:$status,operation:$action,scope:$root,tool:$tool,executable:$executable,argv:$argv,
      nativeExitCode:$code,nativeResult:$native,data:($native.result//$native.error.details),
      nextStep:(if $status=="partial" then "review unavailable ranges and observed-only results" else "review the scoped result; cleanup is a separate action" end),exitCode:$code}'
exit "$code"
