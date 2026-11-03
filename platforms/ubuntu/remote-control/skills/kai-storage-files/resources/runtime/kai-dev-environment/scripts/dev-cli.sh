#!/usr/bin/env bash
set -eu
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
. "$here/../../kai-tool-bootstrap/scripts/jq-env.sh"
kai_use_jq full || exit $?
fail() { jq -cn --argjson code "$1" --arg category "$2" --arg reason "$3" '{schemaVersion:1,status:"failed",category:$category,reason:$reason,exitCode:$code}'; exit "$1"; }
action="${1:-}"; tool="${2:-}"; version="${3:-}"
case "$action" in probe|install|exec) ;; *) fail 2 usage 'dev-cli.sh probe|install|exec uv EXACT_VERSION [-- ARGUMENTS]' ;; esac
[ "$tool" = uv ] || fail 18 unsupported-tool 'the first developer CLI profile is uv; SDKs use runtime.sh'
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 2 version-selection 'select a complete stable developer CLI version'
platform="${KAI_PLATFORM:-$(bash "$here/../../kai-tool-bootstrap/scripts/tool.sh" probe bash | jq -er .platform)}"
case "$platform" in
    istoreos|openwrt)
        if [ "${ISTORE_RUNTIME_ENTERED:-}" != 1 ]; then
            . "$here/runtime-adapter.sh"
            kai_runtime_adapter
            exec sh "$adapter" "$here/enter.sh" "$here/dev-cli.sh" "$@"
        fi ;;
esac
mise="${KAI_MISE_BIN:-$(command -v mise 2>/dev/null || true)}"
[ -n "$mise" ] || { [ ! -x "$HOME/.local/bin/mise" ] || mise="$HOME/.local/bin/mise"; }
if [ "$platform" = windows ] && [ -n "$mise" ]; then mise="$(cygpath -u "$mise")"; fi
[ -n "$mise" ] && [ -x "$mise" ] || fail 127 missing-executable 'prepare an existing mise before using the developer CLI'
export MISE_AUTO_INSTALL=0 MISE_NOT_FOUND_AUTO_INSTALL=0
spec="$tool@$version"
if [ "$action" = install ]; then
    command=("$mise")
    case "${KAI_RUNTIME_ACCELERATION:-none}" in
        none) ;;
        required)
            client="${KAI_KSCLI_BIN:-$(command -v ks-cli 2>/dev/null || true)}"
            [ -n "$client" ] || { [ ! -x "$HOME/.local/bin/ks-cli" ] || client="$HOME/.local/bin/ks-cli"; }
            [ -n "$client" ] && [ -x "$client" ] || fail 127 missing-executable 'explicit acceleration requires an existing ks-cli and service'
            command=("$client" mise) ;;
        *) fail 2 usage 'KAI_RUNTIME_ACCELERATION must be none or required' ;;
    esac
    code=0; "${command[@]}" install "$spec" >&2 || code=$?
    [ "$code" = 0 ] || fail "$code" installation-failed 'native mise installation failed; integrity policy is unchanged'
fi
install_root="$("$mise" where "$spec" 2>/dev/null)" || fail 4 tool-not-installed 'the exact CLI is absent; installation is a separate action'
executable="$("$mise" which "$tool" --tool "$spec" 2>/dev/null)" || fail 4 tool-not-installed 'mise did not resolve an executable for the selected version'
root_path="$install_root"; executable_path="$executable"
if [ "$platform" = windows ]; then
    root_path="$(cygpath -u "$install_root")"; executable_path="$(cygpath -u "$executable")"
fi
[ -d "$root_path" ] && [ -f "$executable_path" ] && [ -x "$executable_path" ] || fail 4 tool-provenance-mismatch 'the selected installation or executable is absent'
root_path="$(CDPATH= cd -- "$root_path" && pwd -P)"
links=0
while [ -L "$executable_path" ]; do
    links=$((links+1)); [ "$links" -le 16 ] || fail 4 tool-provenance-mismatch 'too many executable links'
    destination="$(readlink "$executable_path")"
    case "$destination" in /*) executable_path="$destination" ;; *) executable_path="$(dirname "$executable_path")/$destination" ;; esac
done
executable_path="$(CDPATH= cd -- "$(dirname "$executable_path")" && pwd -P)/$(basename "$executable_path")"
case "$executable_path" in "$root_path"/*) ;; *) fail 4 tool-provenance-mismatch 'the executable is outside the selected mise installation' ;; esac
native_mise=("$mise")
if [ "$platform" = windows ]; then native_mise=(env 'MSYS2_ARG_CONV_EXCL=*' "$mise"); fi
actual="$("${native_mise[@]}" exec "$spec" -- "$executable" --version)" || fail 4 tool-verification-failed 'the selected developer CLI did not execute'
case "$actual" in "uv $version"|"uv $version "*) ;; *) fail 4 tool-verification-failed 'the developer CLI reports a different version' ;; esac
if [ "$action" = exec ]; then
    shift 3; [ "${1:-}" = -- ] || fail 2 usage 'exec requires -- ARGUMENTS'
    shift; [ "$#" -gt 0 ] || fail 2 usage 'a CLI subcommand or argument is required'
    exec "${native_mise[@]}" exec "$spec" -- "$executable" "$@"
fi
jq -cn --arg action "$action" --arg tool "$tool" --arg version "$version" --arg root "$install_root" --arg exe "$executable" \
    '{schemaVersion:1,status:"passed",operation:$action,tool:$tool,version:$version,installRoot:$root,executable:$exe,scope:"none",source:"mise",exitCode:0}'
