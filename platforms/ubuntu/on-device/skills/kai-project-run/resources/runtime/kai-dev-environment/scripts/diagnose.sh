#!/usr/bin/env bash
# Classify saved current evidence; this command never retries an installation.
set -eu
log="${1:-}"; code="${2:-1}"
[ -f "$log" ] && [ ! -L "$log" ] || exit 2
[[ "$code" =~ ^[0-9]+$ ]] && [ "$code" -le 255 ] || exit 2
category=unknown
next='Inspect the original bounded stderr and preserve the installation.'
if grep -Eiq 'certificate|TLS|SSL' "$log"; then
    category=tls-failed
    next='Inspect clock, DNS, certificate roots and the actual endpoint; preserve TLS verification.'
elif grep -Eiq 'checksum|attestation|signature' "$log"; then
    category=integrity-failed
    next='Inspect expected hashes/signatures and the actual source; keep verification enabled.'
elif grep -Eiq 'no (compatible )?precompiled|precompiled.*(not found|unavailable)' "$log"; then
    category=precompiled-unavailable
    next='Inspect the exact version, architecture and libc; select an available prebuilt release without compiling.'
elif grep -Eiq 'no acceptable C compiler|gcc.*not found|cc:.*not found|configure: error' "$log"; then
    category=source-build-rejected
    next='Inspect precompiled-only settings; do not install a compiler or fall back to source.'
elif grep -Eiq 'incorrect integration HOME|missing integrated shims|runtime directory.*(unavailable|not configured)|environment.*(inactive|not activated)' "$log"; then
    category=environment-inactive
    next='Re-enter the target integration and check runtime_dir, HOME and selected SDK paths.'
elif grep -Eiq 'version.*(not found|invalid|mismatch)|resolver.*complete' "$log"; then
    category=version-selection
    next='Inspect the backend version catalog and resolve one compatible complete version.'
elif grep -Eiq 'download|timed out|connection|resolve|404|403' "$log"; then
    category=download-failed
    next='Inspect source availability, service capability, actual ports and current client/gateway logs.'
fi
jq -cn --arg category "$category" --arg next "$next" --argjson code "$code" \
    '{schemaVersion:1,status:"passed",operation:"diagnose",category:$category,originalExitCode:$code,nextStep:$next}'
