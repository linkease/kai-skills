# Compose an installation plan; no installation is performed.
task_make_plan() {
    local requested method manager candidate observed base prefix command artifact='null' storage='null' effects='[]' body input intent
    local backup='null' combined='null' saved no_storage=false package_absent=false package_reused=false provider_contract=null
    input=$(task_request_digest)
    intent=$("$task_jq" -r '.intent//"install"' <<< "$TASK_REQUEST_JSON")
    case "$intent" in install|update|remove) ;; *) task_stop invalid invalid-intent 2 ;; esac
    requested=$("$task_jq" -r '.version//""' <<< "$TASK_REQUEST_JSON")
    method=${1:-$("$task_jq" -r '.method//"auto"' <<< "$TASK_REQUEST_JSON")}
    case "$method" in auto|existing|owner|native-package|istore|container|artifact|release) ;; *) task_stop invalid invalid-installation-method 2 ;; esac
    if [ "$method" = auto ] && [ "$TASK_STORE" = true ]; then
        task_store_catalog
        [ "$TASK_STORE_APP" = null ] || method=istore
    fi
    if [ "$method" = istore ]; then
        TASK_REQUEST_JSON=$("$task_jq" -c '.method="istore"' <<< "$TASK_REQUEST_JSON")
        task_store_plan "$input";return
    fi
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
    if [ "$intent" != update ] && { [ "$method" = auto ] || [ "$method" = existing ]; } && [ "$("$task_jq" -r .satisfies <<< "$observed")" = true ]; then
        method=existing
        body=$("$task_jq" -cn --arg method "$method" --argjson observed "$observed" '{method:$method,observed:$observed}')
    else
        if [ "$method" = existing ]; then task_stop blocked existing-installation-not-suitable 0 "$observed"; fi
        if [ "$TASK_SOFTWARE" = linkspace ] && { [ "$method" = auto ] || [ "$method" = owner ]; };then task_release_plan "$input";return;fi
        if [ "$method" != owner ]; then
            task_native_query
            [ "$("$task_jq" -r '.sourceConflict//false' <<< "$TASK_NATIVE")" != true ] || task_stop needs-ai native-source-conflict 0 "$TASK_NATIVE"
            candidate=$("$task_jq" -r .candidateVersion <<< "$TASK_NATIVE")
            if [ "$intent" = update ]; then
                local registered
                registered=$("$task_jq" -r .installedVersion <<< "$TASK_NATIVE")
                [ -n "$registered" ] || task_stop needs-ai native-package-not-installed 0 "$TASK_NATIVE"
                [ -n "$candidate" ] || task_stop needs-ai no-compatible-native-candidate 0 "$TASK_NATIVE"
                task_native_compare "$("$task_jq" -r .manager <<< "$TASK_NATIVE")" "$registered" "$candidate"
                case "$TASK_COMPARISON" in
                    installed-newer)
                        [ -z "$requested" ] || [ "$requested" = "$registered" ] || task_stop blocked native-downgrade-refused 0 "$TASK_NATIVE"
                        requested=$registered ;;
                    same|candidate-newer) [ -n "$requested" ] || requested=$candidate ;;
                    *) task_stop needs-ai native-version-comparison-required 0 "$TASK_NATIVE" ;;
                esac
                TASK_REQUEST_JSON=$("$task_jq" -c --arg version "$requested" '.version=$version' <<< "$TASK_REQUEST_JSON")
            fi
            if [ "$intent" != remove ] && { task_version_matches "$requested" "$("$task_jq" -r .installedVersion <<< "$TASK_NATIVE")" || task_version_matches "$requested" "$candidate"; }; then method=native-package; fi
        fi
        if [ "$method" = native-package ]; then
            manager=$("$task_jq" -r .manager <<< "$TASK_NATIVE")
            [ -n "$manager" ] || task_stop needs-ai native-package-manager-required 0 "$TASK_NATIVE"
            case "$manager" in scoop|winget) TASK_REQUEST_JSON=$("$task_jq" -c --arg provider "$manager" '.provider=$provider' <<< "$TASK_REQUEST_JSON") ;; esac
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
                case "$manager" in scoop|winget)
                    . "$task_root/windows-operation.sh";task_windows_contract
                    provider_contract=$TASK_WINDOWS_CONTRACT ;;
                esac
            else effects='[]';fi
            TASK_REQUEST_JSON=$("$task_jq" -c '.method="native-package"' <<< "$TASK_REQUEST_JSON")
            body=$("$task_jq" -cn --arg method "$method" --arg version "$candidate" --arg manager "$manager" --argjson absent "$package_absent" --argjson reused "$package_reused" --argjson native "$TASK_NATIVE" --argjson adapter "$provider_contract" '{method:$method,version:$version,manager:$manager,nativeObservation:$native,providerContract:$adapter,packageAlreadyAbsent:$absent,packageAlreadyInstalled:$reused,dataPolicy:"native-manager-policy; no-force-or-explicit-autoremove"}')
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
