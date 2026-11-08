task_owner_digest() {
    local file
    for file in "$task_root"/*.sh "$task_root/releases.lock.json" "$task_root/../jq/jq-install.sh" "$task_root/../jq/artifacts.lock.json"; do
        [ -f "$file" ] && [ ! -L "$file" ] || return 2
        task_digest "$file" || return $?
    done | task_hash_input
}
task_version_matches() {
    local wanted=$1 actual=$2 wanted_epoch actual_epoch
    [ -n "$actual" ] || return 1
    [ -z "$wanted" ] && return 0
    [ "$wanted" = "$actual" ] && return 0
    if [[ "$wanted" == *:* ]];then
        wanted_epoch=${wanted%%:*};actual_epoch=${actual%%:*}
        [ "$wanted_epoch" = "$actual_epoch" ] || return 1
        wanted=${wanted#*:}
    fi
    [[ "$actual" != *:* ]] || actual=${actual#*:}
    # Native packaging revisions may extend an exact upstream release. Alpha,
    # beta, rc and tilde upstream prereleases are not that stable release.
    case "$actual" in
        "$wanted"|"$wanted"-[0-9]*|"$wanted"-r[0-9]*|"$wanted"+dfsg*|"$wanted"+ds[0-9]*|"$wanted"+deb[0-9]*|"$wanted".el[0-9]*) return 0 ;;
        *) return 1 ;;
    esac
}
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
        [ "$probe_code" = 0 ] || task_stop failed existing-program-query-failed "$probe_code" "$("$task_jq" -cn --arg path "$executable" --arg observed "$raw" '{executable:$path,observedVersion:$observed}')"
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
    TASK_OBSERVED=$("$task_jq" -cn --arg path "$executable" --arg version "$version" --arg raw "$raw" --argjson installed "$installed" --argjson valid "$valid" '{installed:$installed,executable:$path,version:$version,observedVersion:$raw,satisfies:$valid,functionalValidation:(if $valid then "passed" else "not-run" end),manager:"existing"}')
}
task_owner_artifact() {
    local raw key value artifact= digest= size= url= version= code
    raw=$(ZSETUP_INSTALLER_MODE=1 sh "$task_root/../jq/jq-install.sh" --plan); code=$?
    [ "$code" = 0 ] || task_stop blocked owner-plan-failed "$code"
    while IFS='=' read -r key value; do
        case "$key" in artifact) artifact=$value ;; sha256) digest=$value ;; size) size=$value ;; url) url=$value ;; version) version=$value ;; esac
    done <<< "$raw"
    [ -n "$artifact" ] && [ -n "$digest" ] && [ -n "$size" ] && [ -n "$url" ] || task_stop failed invalid-owner-plan 11
    TASK_ARTIFACT=$("$task_jq" -cn --arg name "$artifact" --arg sha "$digest" --arg url "$url" --arg version "$version" --argjson size "$size" '{name:$name,sha256:$sha,url:$url,size:$size,version:$version}')
}
task_make_plan() {
    local requested method manager candidate observed base prefix command artifact='null' storage='null' effects='[]' body input intent
    local backup='null' combined='null' saved no_storage=false package_absent=false package_reused=false
    input=$(task_request_digest)
    intent=$("$task_jq" -r '.intent//"install"' <<< "$TASK_REQUEST_JSON")
    case "$intent" in install|remove) ;; *) task_stop invalid invalid-intent 2 ;; esac
    requested=$("$task_jq" -r '.version//""' <<< "$TASK_REQUEST_JSON")
    method=${1:-$("$task_jq" -r '.method//"auto"' <<< "$TASK_REQUEST_JSON")}
    case "$method" in auto|existing|owner|native-package|container|artifact|release) ;; *) task_stop invalid invalid-installation-method 2 ;; esac
    if [ "$method" = container ]; then task_container_plan;return;fi
    if [ "$method" = artifact ]; then task_artifact_plan;return;fi
    if [ "$method" = release ]; then task_release_plan;return;fi
    if [ "$intent" = remove ];then
        case "$method" in
            existing) task_stop blocked program-removal-owner-required 0 ;;
            auto) method=native-package ;;
        esac
    fi
    "$task_jq" -e '(.features//[])|all(.[];.=="jq-regex" or .=="json" or .=="unicode" or .=="bash" or .=="backup-file-level")' <<< "$TASK_REQUEST_JSON" >/dev/null || task_stop needs-ai unknown-functional-requirement 0
    case "$TASK_SOFTWARE" in
        jq) "$task_jq" -e '(.features//[])|all(.[];.=="jq-regex" or .=="json" or .=="unicode")' <<< "$TASK_REQUEST_JSON" >/dev/null || task_stop needs-ai unknown-functional-requirement 0 ;;
        linkspace) "$task_jq" -e '(.features//[])|all(.[];.=="backup-file-level")' <<< "$TASK_REQUEST_JSON" >/dev/null || task_stop needs-ai unknown-functional-requirement 0 ;;
        bash) "$task_jq" -e '(.features//[])|all(.[];.=="bash" or .=="unicode")' <<< "$TASK_REQUEST_JSON" >/dev/null || task_stop needs-ai unknown-functional-requirement 0 ;;
        *) "$task_jq" -e '(.features//[])|length==0' <<< "$TASK_REQUEST_JSON" >/dev/null || task_stop needs-ai unknown-functional-requirement 0 ;;
    esac
    task_observe
    observed=$TASK_OBSERVED
    if { [ "$method" = auto ] || [ "$method" = existing ]; } && [ "$("$task_jq" -r .satisfies <<< "$observed")" = true ]; then
        method=existing
        body=$("$task_jq" -cn --arg method "$method" --argjson observed "$observed" '{method:$method,observed:$observed}')
    else
        if [ "$method" = existing ]; then task_stop blocked existing-installation-not-suitable 0 "$observed"; fi
        if [ "$TASK_SOFTWARE" = linkspace ] && { [ "$method" = auto ] || [ "$method" = owner ]; };then task_release_plan "$input";return;fi
        if [ "$method" != owner ]; then
            task_native_query
            candidate=$("$task_jq" -r .candidateVersion <<< "$TASK_NATIVE")
            if [ "$intent" != remove ] && { task_version_matches "$requested" "$("$task_jq" -r .installedVersion <<< "$TASK_NATIVE")" || task_version_matches "$requested" "$candidate"; }; then method=native-package; fi
        fi
        if [ "$method" = native-package ]; then
            manager=$("$task_jq" -r .manager <<< "$TASK_NATIVE")
            [ -n "$manager" ] || task_stop needs-ai native-package-manager-required 0 "$TASK_NATIVE"
            if [ "$intent" = remove ];then
                candidate=$("$task_jq" -r .installedVersion <<< "$TASK_NATIVE")
                if [ -n "$candidate" ];then task_version_matches "$requested" "$candidate" || task_stop blocked native-installed-version-mismatch 0 "$TASK_NATIVE"
                else no_storage=true;package_absent=true;fi
                effects='["native-package-removal","native-package-hooks"]'
            else
                local installed
                installed=$("$task_jq" -r .installedVersion <<< "$TASK_NATIVE")
                if [ -n "$installed" ] && task_version_matches "$requested" "$installed";then
                    candidate=$installed;package_reused=true;no_storage=true
                else
                    [ -n "${candidate:-}" ] && task_version_matches "$requested" "$candidate" || task_stop needs-ai no-compatible-native-candidate 0 "$TASK_NATIVE"
                fi
                effects='["native-package-operation","native-package-hooks"]'
            fi
            if [ "$no_storage" != true ];then
                [ "$("$task_jq" -r 'has("storage")' <<< "$TASK_REQUEST_JSON")" = true ] || task_stop needs-ai native-package-storage-budget-required 0 "$TASK_NATIVE"
            else effects='[]';fi
            TASK_REQUEST_JSON=$("$task_jq" -c '.method="native-package"' <<< "$TASK_REQUEST_JSON")
            body=$("$task_jq" -cn --arg method "$method" --arg version "$candidate" --arg manager "$manager" --argjson absent "$package_absent" --argjson reused "$package_reused" '{method:$method,version:$version,manager:$manager,packageAlreadyAbsent:$absent,packageAlreadyInstalled:$reused,dataPolicy:"native-manager-policy; no-force-or-explicit-autoremove"}')
        elif [ "$TASK_SOFTWARE" = jq ]; then
            task_owner_artifact
            candidate=$("$task_jq" -r .version <<< "$TASK_ARTIFACT")
            task_version_matches "$requested" "$candidate" || task_stop needs-ai no-compatible-owner-version 0 "$TASK_ARTIFACT"
            method=owner; artifact=$TASK_ARTIFACT
            base=$("$task_jq" -r '.prefixBase//""' <<< "$TASK_REQUEST_JSON")
            [ -n "$base" ] && [ -d "$base" ] || task_stop needs-ai persistent-installation-location-required 0
            prefix=${base%/}/jq; command=$prefix/commands/jq
            case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) command=$command.exe ;; esac
            # Account for archive/staging, version retention and exposed command.
            TASK_REQUEST_JSON=$("$task_jq" -c --arg base "$base" --argjson size "$("$task_jq" .size <<< "$artifact")" '.storage={reserveBytes:8388608,paths:[{role:"download-and-stage",path:$base,bytes:($size*2),inodes:8},{role:"program-old-new-command",path:$base,bytes:($size*3),inodes:12}]}' <<< "$TASK_REQUEST_JSON")
            if [ "$intent" = remove ]; then
                TASK_REQUEST_JSON=$("$task_jq" -c --arg base "$base" '.storage={reserveBytes:65536,paths:[{role:"remove-metadata",path:$base,bytes:65536,inodes:4}]}' <<< "$TASK_REQUEST_JSON")
            fi
            case "$(uname -s)" in Linux) ;; *) TASK_REQUEST_JSON=$("$task_jq" -c '.storage.paths|=map(.inodes=0)' <<< "$TASK_REQUEST_JSON") ;; esac
            effects='["managed-program-files"]'
            body=$("$task_jq" -cn --arg method "$method" --arg version "$candidate" --arg prefix "$prefix" --arg command "$command" --argjson artifact "$artifact" '{method:$method,version:$version,owner:"jq",prefix:$prefix,command:$command,artifact:$artifact}')
        else task_stop needs-ai no-installation-rule 0; fi
        # The storage module accepts the same normalized, in-memory request.
        if [ "$no_storage" != true ];then task_storage_plan;storage=$TASK_STORAGE_PLAN;fi
    fi
    if [ "$method" != existing ] && [ "$no_storage" != true ] && [ "$("$task_jq" -r '.backupRequired//false' <<< "$TASK_REQUEST_JSON")" = true ]; then
        task_backup_plan;backup=$TASK_BACKUP_PLAN
        saved=$TASK_REQUEST_JSON;task_backup_add_budget;task_storage_plan;combined=$TASK_STORAGE_PLAN;TASK_REQUEST_JSON=$saved
    fi
    TASK_PLAN=$("$task_jq" -c --arg intent "$intent" --arg input "$input" --arg request "$(task_request_digest)" --arg owner "$(task_owner_digest)" --argjson storage "$storage" --argjson backup "$backup" --argjson combined "$combined" --argjson effects "$effects" '.+{intent:$intent,inputDigest:$input,requestDigest:$request,ownerDigest:$owner,storagePlan:$storage,backupPlan:$backup,combinedStoragePlan:$combined,effects:$effects}' <<< "$body")
    TASK_PLAN=$("$task_jq" -c --arg digest "$("$task_jq" -cS . <<< "$TASK_PLAN" | task_hash_input)" '.+{planDigest:$digest}' <<< "$TASK_PLAN")
}
task_apply_plan() {
    local expected method digest expected_request owner details code=0 zsetup prefix command saved backup='null'
    expected=$("$task_jq" -c '.plan//null' <<< "$TASK_REQUEST_JSON")
    [ "$expected" != null ] || task_stop blocked missing-plan 0
    [ "$("$task_jq" -r .inputDigest <<< "$expected")" = "$(task_request_digest)" ] || task_stop blocked plan-changed 0
    digest=$("$task_jq" -cS 'del(.planDigest)' <<< "$expected" | task_hash_input)
    [ "$digest" = "$("$task_jq" -r .planDigest <<< "$expected")" ] || task_stop blocked plan-changed 0
    method=$("$task_jq" -r .method <<< "$expected")
    task_make_plan "$method"
    [ "$("$task_jq" -r .requestDigest <<< "$expected")" = "$(task_request_digest)" ] && \
        [ "$("$task_jq" -r .ownerDigest <<< "$expected")" = "$(task_owner_digest)" ] || task_stop blocked plan-changed 0
    # Source, version and paths must still resolve to the reviewed choice.
    [ "$("$task_jq" -cS 'walk(if type=="object" then del(.planDigest,.storagePlan,.combinedStoragePlan) else . end)' <<< "$expected")" = "$("$task_jq" -cS 'walk(if type=="object" then del(.planDigest,.storagePlan,.combinedStoragePlan) else . end)' <<< "$TASK_PLAN")" ] || task_stop blocked plan-changed 0
    if [ "$method" = existing ]; then
        task_observe
        [ "$("$task_jq" -r .satisfies <<< "$TASK_OBSERVED")" = true ] || task_stop blocked existing-installation-not-suitable 0
        task_result success reused 0 "$TASK_OBSERVED"; return
    fi
    if [ "$method" = native-package ] && [ "$("$task_jq" -r .intent <<< "$expected")" = remove ] && [ "$("$task_jq" -r .packageAlreadyAbsent <<< "$expected")" = true ];then
        task_result success native-package-already-absent 0 '{"packageAbsent":true,"otherProgramCopies":"not-checked"}';return
    fi
    if [ "$method" = native-package ] && [ "$("$task_jq" -r .packageAlreadyInstalled <<< "$expected")" = true ];then
        task_observe "" "$("$task_jq" -r .version <<< "$expected")"
        [ "$("$task_jq" -r .installed <<< "$TASK_OBSERVED")" = true ] || task_stop needs-ai installed-functional-check-required 0 "$TASK_NATIVE"
        [ "$("$task_jq" -r .satisfies <<< "$TASK_OBSERVED")" = true ] || task_stop failed functional-verification-failed 11 "$TASK_OBSERVED"
        task_result success reused 0 "$TASK_OBSERVED";return
    fi
    if [ "$("$task_jq" -c .backupPlan <<< "$expected")" != null ]; then
        saved=$TASK_REQUEST_JSON;task_backup_add_budget
        task_storage_check "$("$task_jq" -c .combinedStoragePlan <<< "$expected")";TASK_REQUEST_JSON=$saved
        task_backup_run "$("$task_jq" -c .backupPlan <<< "$expected")";backup=$TASK_BACKUP_RECEIPT
    fi
    task_storage_check "$("$task_jq" -c .storagePlan <<< "$expected")"
    if [ "$method" = container ]; then task_container_apply "$expected";return;fi
    if [ "$method" = artifact ] || [ "$method" = release ]; then task_artifact_apply "$expected";return;fi
    if [ "$method" = native-package ] && [ "$("$task_jq" -r .intent <<< "$expected")" = remove ];then
        TASK_EFFECTS='["native-package-removal-attempt","native-package-hooks"]'
        task_native_remove "$("$task_jq" -r .manager <<< "$expected")"
        task_native_query
        [ -z "$("$task_jq" -r .installedVersion <<< "$TASK_NATIVE")" ] || task_stop failed native-removal-verification-failed 11 "$TASK_NATIVE"
        task_result success removed 0 "$("$task_jq" -c '.+{packageAbsent:true,otherProgramCopies:"not-checked",dataPolicy:"native-manager-policy; no-force-or-explicit-autoremove"}' <<< "$TASK_NATIVE")" "$TASK_EFFECTS";return
    fi
    if [ "$method" = owner ]; then
        zsetup=${ZSETUP_BIN:-${KAI_ZSETUP_BIN:-$(type -P zsetup || true)}}
        [ -n "$zsetup" ] || { [ ! -x "$HOME/.local/bin/zsetup" ] || zsetup=$HOME/.local/bin/zsetup; }
        [ -n "$zsetup" ] && [ -x "$zsetup" ] || task_stop blocked missing-zsetup 127
        prefix=$("$task_jq" -r .prefix <<< "$expected"); command=$("$task_jq" -r .command <<< "$expected")
        set -- --installer-prefix "$prefix" --installer-command "$command"
        [ "$("$task_jq" -r .intent <<< "$expected")" != remove ] || set -- "$@" --remove
        TASK_EFFECTS='["managed-installation-attempt"]'
        ZSETUP_BIN="$zsetup" ZSETUP_INSTALLER_MODE=1 "$zsetup" run -- sh "$task_root/../jq/jq-install.sh" "$@" >&2 || code=$?
        [ "$code" = 0 ] || task_stop failed owner-install-failed "$code"
        if [ "$("$task_jq" -r .intent <<< "$expected")" = remove ]; then
            [ ! -e "$command" ] && [ ! -L "$command" ] || task_stop failed removal-verification-failed 11
            task_result success removed 0 '{"preserved":["config","data","foreign-files"]}' '["managed-program-files"]'; return
        fi
        task_observe "$command"
    else
        TASK_EFFECTS='["native-package-attempt","native-package-hooks"]'
        task_native_install "$("$task_jq" -r .manager <<< "$expected")" "$("$task_jq" -r .version <<< "$expected")"
        task_native_query
        [ "$("$task_jq" -r .installedVersion <<< "$TASK_NATIVE")" = "$("$task_jq" -r .version <<< "$expected")" ] || task_stop failed installed-package-version-mismatch 11 "$TASK_NATIVE"
        task_observe "" "$("$task_jq" -r .installedVersion <<< "$TASK_NATIVE")"
        if [ "$("$task_jq" -r .installed <<< "$TASK_OBSERVED")" != true ]; then
            task_stop needs-ai installed-functional-check-required 0 "$TASK_NATIVE"
        fi
    fi
    [ "$("$task_jq" -r .satisfies <<< "$TASK_OBSERVED")" = true ] || task_stop failed functional-verification-failed 11 "$TASK_OBSERVED"
    details=$("$task_jq" -cn --argjson observed "$TASK_OBSERVED" --argjson plan "$expected" --argjson backup "$backup" '$observed+{installation:{method:$plan.method,version:$plan.version,owner:$plan.owner,planDigest:$plan.planDigest},backup:$backup}')
    task_result success installed 0 "$details" "$("$task_jq" -c .effects <<< "$expected")"
}
