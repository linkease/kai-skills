# Known program identity and explicitly supported functional checks.
task_observe() {
    local executable=${1:-} verified_native=${2:-} raw= version= wanted= probe_code=0 installed=false valid=false binary=$TASK_SOFTWARE
    [ "$TASK_SOFTWARE" != ripgrep ] || binary=rg
    [ "$TASK_SOFTWARE" != fastnet ] || binary=FastNet
    case "$TASK_SOFTWARE" in bash|jq|ripgrep|git|curl|ks-cli|fastnet|linkspace) ;;
        *) TASK_OBSERVED='{"installed":false,"satisfies":false,"functionalValidation":"not-run"}'; return ;;
    esac
    [ -n "$executable" ] || executable=$(type -P "$binary" || true)
    if [ -n "$executable" ] && [ -f "$executable" ]; then
        case "$TASK_SOFTWARE" in ks-cli|fastnet|linkspace) set -- version ;; *) set -- --version ;; esac
        raw=$("$executable" "$@" 2>/dev/null | head -c 8192) || probe_code=$?
        [ "$probe_code" = 0 ] || task_stop failed existing-program-query-failed "$probe_code" "$("$task_jq" -cn --arg path "$executable" '{executable:$path}')"
        version=$("$task_jq" -r '(.version//.result.version//empty)|select(type=="string")' <<< "$raw" 2>/dev/null) || version=
        if [ -z "$version" ];then
            version=$("$task_jq" -rn --arg value "$raw" 'try ($value|capture("(?<v>[0-9]+\\.[0-9]+(?:\\.[0-9]+)?(?:[-+][A-Za-z0-9.-]+)?)").v) catch ""')
        fi
        [ -z "$version" ] || installed=true
        wanted=$("$task_jq" -r '.version//""' <<< "$TASK_REQUEST_JSON")
        if [ "$installed" = true ] && { [ -z "$wanted" ] || [ "$wanted" = "$version" ] || { [ "$wanted" = "$verified_native" ] && task_version_matches "$version" "$verified_native"; }; }; then
            valid=true
            case "$TASK_SOFTWARE" in
                jq) "$executable" -ne '("abc"|test("^a")) and (("abc"|sub("^a";"x"))=="xbc") and (({s:"中文"}|tojson|fromjson|.s)=="中文")' >/dev/null 2>&1 || valid=false ;;
                bash) "$executable" -c '[[ abc == a* ]] && v=中文 && test "${v}" = 中文' || valid=false ;;
                linkspace)
                    if [ "$("$task_jq" -r '(.features//[])|index("backup-file-level")!=null' <<< "$TASK_REQUEST_JSON")" = true ];then
                        case "$version" in 0.0.*|0.1.*) valid=false ;;
                            *)
                                local contract= feature_code=0
                                contract=$("$executable" backup version 2>/dev/null | head -c 8192) || feature_code=$?
                                [ "$feature_code" = 0 ] || task_stop failed existing-program-feature-query-failed "$feature_code"
                                "$task_jq" -e --arg version "$version" '.schemaVersion==1 and .status=="succeeded" and .result.version==$version' <<< "$contract" >/dev/null || task_stop failed existing-program-feature-contract 11 ;;
                        esac
                    fi ;;
            esac
        fi
    fi
    TASK_OBSERVED=$("$task_jq" -cn --arg path "$executable" --arg version "$version" --argjson installed "$installed" --argjson valid "$valid" '{installed:$installed,executable:$path,version:$version,observedVersion:$version,satisfies:$valid,functionalValidation:(if $valid then "passed" else "not-run" end),manager:"existing"}')
}
