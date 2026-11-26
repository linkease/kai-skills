#!/usr/bin/env bash
set -eu
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
. "$here/../../kai-tool-bootstrap/scripts/jq-env.sh"
kai_use_jq full || exit $?
fail() { jq -cn --arg reason "$1" '{schemaVersion:1,status:"failed",operation:"verify-evidence",category:"evidence-format",reason:$reason,accelerationValidation:"insufficient-evidence",exitCode:4}'; exit 4; }
[ "$#" = 3 ] || fail 'evidence.sh MANIFEST CLIENT_LOG GATEWAY_LOG'
for path in "$@"; do
    [ -f "$path" ] && [ "$(wc -c < "$path")" -le 67108864 ] || fail 'evidence inputs must be regular files bounded to 64MiB each'
done
sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d ' ' -f 1
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d ' ' -f 1
    else return 127; fi
}
client_sha="$(sha256 "$2")" || fail 'SHA256 utility unavailable'
gateway_sha="$(sha256 "$3")" || fail 'SHA256 utility unavailable'
result="$(jq -n --slurpfile manifest "$1" --rawfile logs "$3" --arg clientSha "$client_sha" --arg gatewaySha "$gateway_sha" \
    -f "$here/evidence.jq")" || fail 'invalid evidence schema or observation data'
printf '%s\n' "$result"
exit "$(printf '%s' "$result" | jq -er .exitCode)"
