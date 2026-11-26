#!/bin/sh
# Classify evidence; the caller keeps responsibility for the original exit code.
set -eu
log="${1:?a log file is required}"
[ -f "$log" ] || { echo 'failed: missing log file' >&2; exit 2; }
if grep -Eiq 'realpath.*(not found|No such file)|realpath:.*not found' "$log"; then
  echo 'diagnosis=pip-launcher-realpath: matched log pattern; heuristic evidence only'
elif grep -Eiq 'no (precompiled|compatible).*python|precompiled.*(not found|unavailable)|no precompiled' "$log"; then
  echo 'diagnosis=precompiled-unavailable: matched log pattern; heuristic evidence only'
elif grep -Eiq 'no acceptable C compiler|gcc.*not found|cc:.*not found|configure: error' "$log"; then
  echo 'diagnosis=source-build: matched log pattern; heuristic evidence only'
elif grep -Eiq 'not.*virtualenv|externally.managed|VIRTUAL_ENV|venv.*activat' "$log"; then
  echo 'diagnosis=venv-not-active: matched log pattern; heuristic evidence only'
elif grep -Eiq 'checksum|attestation|signature|certificate|TLS|SSL' "$log"; then
  echo 'diagnosis=integrity-or-tls: matched log pattern; heuristic evidence only'
elif grep -Eiq 'version.*(not found|invalid)|latest|3\.9\.9' "$log"; then
  echo 'diagnosis=version-selection: matched log pattern; heuristic evidence only'
elif grep -Eiq 'download|timed out|connection|resolve|404|403' "$log"; then
  echo 'diagnosis=download: matched log pattern; heuristic evidence only'
else
  echo 'diagnosis=unclassified: matched log pattern; heuristic evidence only'
fi
