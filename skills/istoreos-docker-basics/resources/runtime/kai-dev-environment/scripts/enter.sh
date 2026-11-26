#!/bin/sh
# mise-exec's file adapter executes POSIX sh; enter Bash explicitly afterwards.
set -eu
exec bash "$@"
