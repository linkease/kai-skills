#!/usr/bin/env bash
set -euo pipefail
op_name=service.apply
op_here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$op_here/write-lib.sh"
[ "$#" = 1 ] || op_fail INVALID_ARGUMENT 'Usage: apply.sh REQUEST_JSON; service, action and observed preconditions must be explicit.' 2
op_init "$1"
jq -e '.parameters|((keys-["operationId","service","action","configName","expectedInitSHA256","expectedConfigSHA256","uci","verification","timeoutSeconds"])|length==0) and
  (.service|type=="string" and test("^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$") and (contains("..")|not)) and
  (.configName|type=="string" and test("^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$")) and
  (.action as $a|["start","stop","restart","enable","disable","none"]|index($a)!=null) and
  (.expectedInitSHA256|type=="string" and test("^[a-f0-9]{64}$")) and
  (.expectedConfigSHA256|type=="string" and test("^([a-f0-9]{64}|absent)$")) and
  (.verification|type=="object") and
  (.verification.kind as $k|["procd-running","procd-stopped","init-enabled","init-disabled","docker-api","uci-value"]|index($k)!=null) and
  (if .uci==null then .action!="none" else (.uci|type=="object" and (keys==["expectedValue","key","value"]) and ([.key,.value,.expectedValue]|all(type=="string" and length<=512 and (test("[[:cntrl:]]")|not))) and (.key|test("^[A-Za-z0-9_-]+\\.[A-Za-z0-9_@\\[\\]-]+\\.[A-Za-z0-9_-]+$"))) end)' <<< "$op_request" >/dev/null || op_fail INVALID_ARGUMENT 'Select an exact service action, configuration identity and supported verification; no enable key or service action is inferred.' 2
op_service=$(jq -r .parameters.service <<< "$op_request")
op_action=$(jq -r .parameters.action <<< "$op_request")
op_config=$(jq -r .parameters.configName <<< "$op_request")
op_kind=$(jq -r .parameters.verification.kind <<< "$op_request")
op_root=${ISTOREOS_ROOT:-};op_root=${op_root%/}
op_init_file="$op_root/etc/init.d/$op_service"
op_config_file="$op_root/etc/config/$op_config"
op_init_digest=$(jq -r .parameters.expectedInitSHA256 <<< "$op_request")
op_config_digest=$(jq -r .parameters.expectedConfigSHA256 <<< "$op_request")
[ "${KAIPLUS_CONFIRMED:-}" = 1 ] || op_fail AUTHORIZATION_REQUIRED 'This CLI requires an existing scoped authorization marker; it does not grant host permissions.' 2
op_expected_hash "$op_init_file" "$op_init_digest"
op_expected_hash "$op_config_file" "$op_config_digest"
[ -x "$op_init_file" ] || op_fail PRECONDITION_UNAVAILABLE 'The selected native service entry is not executable.' 2
op_executor
case "$op_action:$op_kind" in
    start:procd-running|restart:procd-running|stop:procd-stopped|enable:init-enabled|disable:init-disabled|none:uci-value|start:docker-api|restart:docker-api) ;;
    *) op_fail INVALID_ARGUMENT 'The verification does not match the selected operation.' 2 ;;
esac
if [ "$op_service" = dockerd ] && { [ "$op_action" = start ] || [ "$op_action" = restart ]; }; then
    [ "$op_kind" = docker-api ] || op_fail INVALID_ARGUMENT 'Docker start/restart requires the explicitly selected engine API and data-root postconditions.' 2
fi
if [ "$op_kind" = docker-api ]; then
    jq -e '.parameters.verification|keys==["endpoint","expectedDataRoot","expectedEngineId","kind"] and
      (.endpoint|type=="string" and startswith("unix:///") and (test("[\\r\\n?@]")|not)) and
      (.expectedDataRoot|type=="string" and startswith("/") and length<=512) and
      (.expectedEngineId|type=="string" and length>0 and length<=200)' <<< "$op_request" >/dev/null || op_fail INVALID_ARGUMENT 'Docker verification requires an explicit local endpoint, engine identity and data root.' 2
fi
op_has_uci=false
if jq -e '.parameters.uci!=null' <<< "$op_request" >/dev/null; then
    op_has_uci=true
    op_uci_key=$(jq -r .parameters.uci.key <<< "$op_request")
    op_uci_value=$(jq -r .parameters.uci.value <<< "$op_request")
    op_uci_expected=$(jq -r .parameters.uci.expectedValue <<< "$op_request")
    [[ "$op_uci_key" = "$op_config."* ]] || op_fail INVALID_ARGUMENT 'The selected UCI key is outside the declared configuration.' 2
    command -v uci >/dev/null 2>&1 || op_fail DEPENDENCY_UNAVAILABLE 'The existing native UCI command is unavailable.' 2
    # Use a private, uniquely named package. Changing savedir alone does not
    # remove UCI's default delta search path, and -P suppresses commit.
    # A private package cannot commit unrelated pending changes for the real name.
    mkdir -- "$op_job/uci" "$op_job/config"
    op_private_config="kai_operation_${RANDOM}_${RANDOM}"
    op_candidate="$op_job/config/$op_private_config"
    cp -p -- "$op_config_file" "$op_candidate" || op_fail PRECONDITION_UNAVAILABLE 'Cannot create the owned configuration candidate.'
    op_uci=(uci -q -c "$op_job/config" -t "$op_job/uci")
    op_private_key="$op_private_config.${op_uci_key#*.}"
    op_native "${op_uci[@]}" get "$op_private_key" || op_fail PRECONDITION_UNAVAILABLE 'The existing UCI value could not be read; absent keys are not inferred.'
    [ "$(cat "$op_job/native.stdout")" = "$op_uci_expected" ] || op_fail PRECONDITION_CHANGED 'The selected UCI value changed after observation.'
    op_effect config-stage stage-uci "$op_job/uci"
    op_effect config-commit commit-private-uci "$op_candidate"
    op_effect config-activate activate-configuration "$op_config_file"
fi
if [ "$op_action" != none ]; then op_effect service-command native-service-action "$op_init_file:$op_action"; fi
op_fact service "$(jq -cn --arg service "$op_service" --arg action "$op_action" '{name:$service,action:$action,applicationHealth:"not-inferred-from-command"}')" 'explicit operation parameters'
if [ "$op_has_uci" = true ]; then
    op_run_effect config-stage "${op_uci[@]}" set "$op_private_key=$op_uci_value"
    op_expected_hash "$op_config_file" "$op_config_digest"
    op_run_effect config-commit "${op_uci[@]}" commit "$op_private_config"
    op_native "${op_uci[@]}" get "$op_private_key" || op_fail VERIFICATION_FAILED 'The committed candidate cannot be read.'
    op_equal=false;[ "$(cat "$op_job/native.stdout")" != "$op_uci_value" ] || op_equal=true
    op_check committed-value "$op_equal" 'native UCI readback of the explicitly selected key'
    op_activation_temporary=$(mktemp "$op_root/etc/config/.kai-operation.XXXXXX") || op_fail PRECONDITION_UNAVAILABLE 'Cannot create an owned activation file on the configuration filesystem.'
    op_native cp -p -- "$op_candidate" "$op_activation_temporary" || op_fail NATIVE_STAGE_FAILED 'Cannot stage the verified candidate on its destination filesystem.'
    op_expected_hash "$op_config_file" "$op_config_digest"
    op_run_effect config-activate mv -- "$op_activation_temporary" "$op_config_file"
    op_activation_temporary=
    op_expected_hash "$op_config_file" "$(op_hash "$op_candidate")"
fi
if [ "$op_action" != none ]; then
    op_expected_hash "$op_init_file" "$op_init_digest"
    if [ "$op_has_uci" != true ]; then op_expected_hash "$op_config_file" "$op_config_digest"; fi
    op_run_effect service-command "$op_init_file" "$op_action"
fi
case "$op_kind" in
    procd-running|procd-stopped)
        op_native ubus call service list "$(jq -cn --arg service "$op_service" '{name:$service}')" || op_fail VERIFICATION_UNAVAILABLE 'Native procd service state could not be read.'
        op_pass=false
        if [ "$op_kind" = procd-running ]; then
            jq -e --arg service "$op_service" '[.[$service].instances//{}|.[]]|length>0 and all(.[];.running==true)' "$op_job/native.stdout" >/dev/null && op_pass=true
        else
            jq -e --arg service "$op_service" 'type=="object" and ([.[$service].instances//{}|.[]]|all(.[];.running==false))' "$op_job/native.stdout" >/dev/null && op_pass=true
        fi
        op_check "$op_kind" "$op_pass" 'native procd instance state; does not establish application API health'
        ;;
    init-enabled|init-disabled)
        op_native "$op_init_file" enabled || :
        op_code=$op_native_code
        op_pass=false
        if [ "$op_kind" = init-enabled ] && [ "$op_code" = 0 ]; then op_pass=true; fi
        if [ "$op_kind" = init-disabled ] && [ "$op_code" = 1 ]; then op_pass=true; fi
        op_check "$op_kind" "$op_pass" 'native init enable-state query'
        ;;
    docker-api)
        op_endpoint=$(jq -r .parameters.verification.endpoint <<< "$op_request")
        op_native env -u DOCKER_HOST -u DOCKER_CONTEXT docker --host "$op_endpoint" info --format '{{json .}}' || op_fail VERIFICATION_UNAVAILABLE 'The selected Docker API is unavailable; process presence does not establish success.'
        op_pass=false
        jq -e --arg id "$(jq -r .parameters.verification.expectedEngineId <<< "$op_request")" --arg root "$(jq -r .parameters.verification.expectedDataRoot <<< "$op_request")" '.ID==$id and .DockerRootDir==$root and (.ServerVersion|type=="string" and length>0)' "$op_job/native.stdout" >/dev/null && op_pass=true
        op_check selected-docker-api-and-root "$op_pass" 'explicit local Docker engine API, engine ID, ServerVersion and DockerRootDir'
        ;;
    uci-value) [ "$op_has_uci" = true ] || op_fail VERIFICATION_INCOMPLETE 'No explicit configuration operation was selected.' ;;
esac
op_expected_hash "$op_init_file" "$op_init_digest"
op_check init-source-preserved true 'native entry SHA256 unchanged; no persistent guard was installed'
op_success
