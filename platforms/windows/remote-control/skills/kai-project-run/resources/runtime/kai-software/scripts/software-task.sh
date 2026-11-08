#!/usr/bin/env bash
set -eu
set -o pipefail
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/../../kai-tool-bootstrap/scripts/jq-env.sh"
kai_use_jq full || exit $?
. "$here/owner-env.sh"
if ! owner=$(kai_software_owner_root);then
    printf '%s\n' '{"protocol":"software-task/v1","schemaVersion":1,"operation":null,"targetId":null,"software":null,"status":"blocked","reason":"owner-resource-integrity","nativeExitCode":11,"effects":[],"details":{}}'
    exit 21
fi
export ZSETUP_TASK_JQ="$KAI_JQ_BIN"
exec bash "$owner/software/task.sh" "$@"
