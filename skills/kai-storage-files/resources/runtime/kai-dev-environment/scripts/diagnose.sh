#!/usr/bin/env bash
# Classify saved current evidence; this command never retries an installation.
set -eu
log="${1:-}"; code="${2:-1}"
[ -f "$log" ] && [ ! -L "$log" ] || exit 2
[[ "$code" =~ ^[0-9]+$ ]] && [ "$code" -le 255 ] || exit 2
category=unknown

if grep -Eiq 'certificate|TLS|SSL' "$log"; then
    category=tls-failed

elif grep -Eiq 'checksum|attestation|signature' "$log"; then
    category=integrity-failed

elif grep -Eiq 'no (compatible )?precompiled|precompiled.*(not found|unavailable)' "$log"; then
    category=precompiled-unavailable

elif grep -Eiq 'no acceptable C compiler|gcc.*not found|cc:.*not found|configure: error' "$log"; then
    category=source-build-rejected

elif grep -Eiq 'incorrect integration HOME|missing integrated shims|runtime directory.*(unavailable|not configured)|environment.*(inactive|not activated)' "$log"; then
    category=environment-inactive

elif grep -Eiq 'version.*(not found|invalid|mismatch)|resolver.*complete' "$log"; then
    category=version-selection

elif grep -Eiq 'download|timed out|connection|resolve|404|403' "$log"; then
    category=download-failed

fi
jq -cn --arg source "$log" --arg category "$category" --argjson code "$code" \
    '{schemaVersion:1,status:"passed",operation:"diagnose",category:$category,classification:"heuristic-pattern-match",source:$source,originalExitCode:$code}'
