#!/usr/bin/env bash
# Explicit native checkpoint interface; no legacy archive/backend fallback.
set -euo pipefail
op_name=recovery.backup
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/recovery-operation.sh"
