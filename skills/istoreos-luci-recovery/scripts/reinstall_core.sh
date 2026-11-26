#!/usr/bin/env bash
# Compatibility entry: one explicitly selected, verified local opkg artifact.
set -euo pipefail
op_name=package.reinstall
op_here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$op_here/../resources/runtime/istoreos-service-manager/scripts/write-lib.sh"
[ "$#" = 1 ] || op_fail INVALID_ARGUMENT 'Usage: reinstall_core.sh REQUEST_JSON; no package group, feed refresh or service restart is inferred.' 2
op_init "$1"
jq -e '.parameters|((keys-["operationId","manager","package","version","artifact","sha256","timeoutSeconds"])|length==0) and (.manager=="opkg") and (.package|type=="string" and test("^[A-Za-z0-9][A-Za-z0-9.+_-]{0,127}$")) and (.version|type=="string" and length>0 and length<128 and (test("[[:cntrl:][:space:]]")|not)) and (.artifact|type=="string" and startswith("/") and length<=512 and (test("[[:cntrl:]]")|not)) and (.sha256|type=="string" and test("^[a-f0-9]{64}$"))' <<< "$op_request" >/dev/null || op_fail INVALID_ARGUMENT 'An exact opkg package/version and verified local artifact are required. Other managers use their explicit native interfaces.' 2
[ "${KAIPLUS_CONFIRMED:-}" = 1 ] || op_fail AUTHORIZATION_REQUIRED 'An existing scoped executor authorization is required.' 2
op_executor
command -v opkg >/dev/null 2>&1 || op_fail DEPENDENCY_UNAVAILABLE 'The explicitly selected manager is unavailable; no fallback was installed.' 2
package=$(jq -r .parameters.package <<< "$op_request")
version=$(jq -r .parameters.version <<< "$op_request")
artifact=$(jq -r .parameters.artifact <<< "$op_request")
sha=$(jq -r .parameters.sha256 <<< "$op_request")
op_expected_hash "$artifact" "$sha"
cp -p -- "$artifact" "$op_job/package.ipk"
op_expected_hash "$op_job/package.ipk" "$sha"
op_native opkg info "$op_job/package.ipk" || op_fail PRECONDITION_UNAVAILABLE 'The selected native manager could not inspect the artifact.'
metadata=$(awk -v package="$package" -v version="$version" 'BEGIN{RS="";FS="\n"} {p="";v="";for(i=1;i<=NF;i++){if($i~/^Package: /)p=substr($i,10);if($i~/^Version: /)v=substr($i,10)}if(p==package&&v==version)n++}END{print n+0}' "$op_job/native.stdout")
[ "$metadata" = 1 ] || op_fail PRECONDITION_CHANGED 'Artifact metadata does not uniquely match the selected package and version.'
op_fact package "$(jq -cn --arg name "$package" --arg version "$version" --arg sha "$sha" '{manager:"opkg",name:$name,version:$version,artifactSHA256:$sha,serviceHealth:"not-inferred"}')" 'explicit local artifact SHA256 and native package metadata; package hooks can have additional effects'
# Reinstall means the exact currently installed version, not an implicit install,
# upgrade or downgrade after the caller observed another database state.
op_native opkg status "$package" || op_fail PRECONDITION_CHANGED 'The selected package is not currently installed; no installation direction was inferred.'
current=$(awk -v package="$package" -v version="$version" 'BEGIN{RS="";FS="\n"} {p="";v="";s="";for(i=1;i<=NF;i++){if($i~/^Package: /)p=substr($i,10);if($i~/^Version: /)v=substr($i,10);if($i~/^Status: /)s=substr($i,9)}if(p==package&&v==version&&s=="install ok installed")n++}END{print n+0}' "$op_job/native.stdout")
[ "$current" = 1 ] || op_fail PRECONDITION_CHANGED 'The current installed version no longer matches this explicit reinstall request.'
op_effect package-reinstall native-package-reinstall "$package"
op_run_effect package-reinstall opkg install --force-reinstall "$op_job/package.ipk"
op_native opkg status "$package" || op_fail VERIFICATION_UNAVAILABLE 'Installed package state could not be read.'
installed=$(awk -v package="$package" -v version="$version" 'BEGIN{RS="";FS="\n"} {p="";v="";s="";for(i=1;i<=NF;i++){if($i~/^Package: /)p=substr($i,10);if($i~/^Version: /)v=substr($i,10);if($i~/^Status: /)s=substr($i,9)}if(p==package&&v==version&&s=="install ok installed")n++}END{print n+0}' "$op_job/native.stdout")
op_check installed-exact-version "$([ "$installed" = 1 ] && echo true || echo false)" 'actual native package database; no web UI or application health claim'
op_success
