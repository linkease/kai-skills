# Revalidate a reviewed plan before any write and verify the actual result.
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
    if [ "$method" = istore ] && [ "$("$task_jq" -r .alreadyCurrent <<< "$expected")" = true ]; then
        task_result success native-channel-already-current 0 "$("$task_jq" -c .observed <<< "$expected")";return
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
    if [ "$method" = istore ]; then task_store_apply "$expected";return;fi
    if [ "$method" = container ]; then task_container_apply "$expected";return;fi
    if [ "$method" = artifact ] || [ "$method" = release ]; then task_artifact_apply "$expected";return;fi
    if [ "$method" = native-package ] && [ "$("$task_jq" -r .intent <<< "$expected")" = remove ];then
        TASK_EFFECTS='["native-package-removal-attempt","native-package-hooks"]'
        TASK_WINDOWS_REVIEWED_CONTRACT=$("$task_jq" -c '.providerContract//null' <<< "$expected")
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
        ZSETUP_BIN="$zsetup" ZSETUP_INSTALLER_MODE=1 "$zsetup" run -- \
            sh "$task_root/../apps/jq/0.1.0/installer.sh" "$@" >&2 || code=$?
        [ "$code" = 0 ] || task_stop failed owner-install-failed "$code"
        if [ "$("$task_jq" -r .intent <<< "$expected")" = remove ]; then
            [ ! -e "$command" ] && [ ! -L "$command" ] || task_stop failed removal-verification-failed 11
            task_result success removed 0 '{"preserved":["config","data","foreign-files"]}' '["managed-program-files"]'; return
        fi
        task_observe "$command"
    else
        TASK_EFFECTS='["native-package-attempt","native-package-hooks"]'
        TASK_WINDOWS_REVIEWED_CONTRACT=$("$task_jq" -c '.providerContract//null' <<< "$expected")
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
