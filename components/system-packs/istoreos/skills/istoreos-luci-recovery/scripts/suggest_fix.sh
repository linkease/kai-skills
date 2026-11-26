#!/bin/sh
# Historical interface name. Reports ownership facts; no prescribed repair plan.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec sh "$here/trace_owner.sh" "${1:?an absolute source path is required}"
