#!/usr/bin/env bash
set -eu
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
. "$here/../resources/runtime/kai-tool-bootstrap/scripts/jq-env.sh"
kai_use_jq full || exit $?
platform="${KAI_PLATFORM:-$(bash "$here/../resources/runtime/kai-tool-bootstrap/scripts/tool.sh" probe bash | jq -er .platform)}"
fail() { jq -cn --arg category "$2" --arg reason "$3" --argjson code "$1" '{schemaVersion:1,status:"failed",category:$category,reason:$reason,exitCode:$code}'; exit "$1"; }
action="${1:-}"; runtime="${2:-}"; version="${3:-}"
case "$action" in resolve|probe|install|verify|exec) ;; *) fail 2 usage 'runtime.sh resolve|probe|install|verify|exec RUNTIME VERSION [SCOPE|-- COMMAND...]' ;; esac
case "$runtime" in python|node|go) ;; *) fail 2 usage 'supported runtimes: python, node, go' ;; esac
if [ "$action" = resolve ]; then
    [[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail 2 version-selection 'invalid runtime version selector'
else
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 2 version-selection 'a complete stable version is required'
fi
scope="${4:-none}"
if [ "$action" = install ]; then
    case "$scope" in none|project|global) ;; *) fail 2 usage 'scope must be none, project or global' ;; esac
fi
if [ "$platform" = istoreos ] || [ "$platform" = openwrt ]; then
    if [ "${ISTORE_RUNTIME_ENTERED:-}" != 1 ]; then
        . "$here/runtime-adapter.sh"
        kai_runtime_adapter
        if [ "$action" = exec ]; then exec sh "$adapter" "$here/enter.sh" "$here/runtime.sh" "$@"; fi
        integration_code=0
        response="$(sh "$adapter" "$here/enter.sh" "$here/runtime.sh" "$@")" || integration_code=$?
        if printf '%s' "$response" | jq -e 'type == "object" and .schemaVersion == 1' >/dev/null 2>&1; then
            printf '%s\n' "$response"
            exit "$integration_code"
        fi
        case "$integration_code" in 130|143) fail "$integration_code" canceled 'runtime integration was canceled' ;; esac
        [ "$integration_code" != 0 ] || integration_code=4
        fail "$integration_code" environment-inactive 'target runtime integration did not return a structured result; inspect original stderr'
    fi
fi
mise="${KAI_MISE_BIN:-$(command -v mise 2>/dev/null || true)}"
[ -n "$mise" ] || { [ ! -x "$HOME/.local/bin/mise" ] || mise="$HOME/.local/bin/mise"; }
[ -n "$mise" ] || fail 127 missing-executable 'ensure mise with kai-tool-bootstrap first'
mise_command=("$mise")
case "${KAI_RUNTIME_ACCELERATION:-none}" in
    none) ;;
    required)
        client="${KAI_KSCLI_BIN:-$(command -v ks-cli 2>/dev/null || true)}"
        [ -n "$client" ] || { [ ! -x "$HOME/.local/bin/ks-cli" ] || client="$HOME/.local/bin/ks-cli"; }
        [ -n "$client" ] && [ -x "$client" ] || fail 127 missing-executable 'explicit acceleration requires an existing ks-cli; it does not start a service'
        export PATH="$(dirname "$mise"):$PATH"
        mise_command=("$client" mise) ;;
    *) fail 2 usage 'KAI_RUNTIME_ACCELERATION must be none or required' ;;
esac
if [ "$action:$runtime:${KAI_GO_GIT_METADATA:-none}" = install:go:required ]; then
    [ "${KAI_RUNTIME_ACCELERATION:-none}" = required ] || fail 2 usage 'Go Git metadata routing requires explicit runtime acceleration'
    command -v git >/dev/null 2>&1 || fail 127 missing-executable 'Go catalog fallback needs native Git with HTTPS transport; install it with kai-software'
    code=0; git_doctor="$("$client" doctor git --json)" || code=$?
    [ "$code" = 0 ] || fail "$code" acceleration-unavailable 'read-only Git Doctor failed; inspect the existing gateway'
    printf '%s' "$git_doctor" | jq -e '.schema_version == 1 and .tool == "git" and .overall == "pass"' >/dev/null || fail 4 acceleration-unavailable 'Git Doctor did not confirm readiness'
    code=0; git_plan="$("$client" --explain --json git ls-remote --tags --refs https://github.com/golang/go 'go*')" || code=$?
    [ "$code" = 0 ] || fail "$code" acceleration-unavailable 'cannot obtain the read-only Git catalog plan'
    printf '%s' "$git_plan" | jq -e '
      .schema_version == 1 and .command[0] == "git" and (.environment|type == "object") and
      (.environment.GIT_CONFIG_COUNT|type == "string" and test("^[0-9]+$")) and
      (.environment|to_entries|all(.[]; (.key|test("^GIT_CONFIG_(COUNT|KEY_[0-9]+|VALUE_[0-9]+)$")) and (.value|type == "string" and index("\u0000") == null)))
    ' >/dev/null || fail 4 acceleration-unavailable 'unsupported Git environment plan; preserve the target configuration'
    while IFS= read -r -d '' metadata_entry; do export "$metadata_entry"; done < <(
        printf '%s' "$git_plan" | jq -j '.environment|to_entries[]|(.key+"="+.value+"\u0000")'
    )
fi
export MISE_AUTO_INSTALL=0 MISE_NOT_FOUND_AUTO_INSTALL=0
if [ "$platform" = windows ] && [ -n "${MISE_DATA_DIR:-}" ]; then
    # An explicitly isolated mise root must not inherit another root's shims.
    # pip probes optional rustc for its User-Agent; a stale Windows mise shim
    # can spawn descendants whose output pipe outlives pip's timeout.
    selected_shims="$(cygpath -u "$MISE_DATA_DIR")/shims"
    remaining_path="$PATH"; selected_path=; separator=
    while :; do
        entry="${remaining_path%%:*}"; keep=1
        case "$entry" in
            */[Mm][Ii][Ss][Ee]/[Ss][Hh][Ii][Mm][Ss])
                [ "$entry" = "$selected_shims" ] || keep=0 ;;
        esac
        if [ "$keep" = 1 ]; then selected_path="$selected_path$separator$entry"; separator=:; fi
        case "$remaining_path" in *:*) remaining_path="${remaining_path#*:}" ;; *) break ;; esac
    done
    export PATH="$selected_path"
fi
spec="$runtime@$version"
case "$platform:$runtime:$action" in
    istoreos:python:install|istoreos:python:verify|istoreos:python:exec|openwrt:python:install|openwrt:python:verify|openwrt:python:exec)
        . "$here/python-openssl.sh"
        python_openssl_environment "$here" ;;
esac
if [ "$action" = resolve ]; then
    resolved="$("$mise" latest "$spec")" || fail "$?" version-selection 'mise version resolution failed'
    [[ "$resolved" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 4 version-selection 'resolver did not return a complete stable version'
    case "$version" in
        [0-9]*) case "$resolved" in "$version"|"$version".*) ;; *) fail 4 version-selection 'resolved version does not match numeric selector' ;; esac ;;
    esac
    jq -cn --arg runtime "$runtime" --arg request "$version" --arg resolved "$resolved" '{schemaVersion:1,status:"passed",runtime:$runtime,requestedVersion:$request,resolvedVersion:$resolved,exitCode:0}'
    exit 0
fi
if [ "$action" = install ]; then
    export MISE_PYTHON_COMPILE=0 MISE_NODE_VERIFY=1 MISE_GO_SKIP_CHECKSUM=0
    unset MISE_NODE_MIRROR_URL
    if [ "$runtime" = python ]; then
        case "$platform" in
            ubuntu|debian|linux|istoreos|openwrt)
                arch="$(uname -m)"; case "$arch" in x86_64|aarch64) ;; *) fail 4 unsupported-architecture 'no frozen precompiled Python mapping' ;; esac
                libc=unknown
                for loader in /lib/ld-musl-*.so*; do [ ! -e "$loader" ] || libc=musl; done
                if [ "$libc" = unknown ] && getconf GNU_LIBC_VERSION >/dev/null 2>&1; then libc=gnu; fi
                [ "$libc" != unknown ] || fail 4 unknown-libc 'cannot select a precompiled Python archive'
                export MISE_PYTHON_PRECOMPILED_ARCH="$arch" MISE_PYTHON_PRECOMPILED_OS="unknown-linux-$libc" ;;
            macos|windows) ;; *) fail 4 unsupported-platform 'no precompiled runtime policy for this platform' ;;
        esac
    fi
    code=0; "${mise_command[@]}" install "$spec" >&2 || code=$?
    [ "$code" = 0 ] || fail "$code" installation-failed 'mise installation failed; precompiled-only and integrity settings remain enabled'
fi
installed_dir="$("$mise" where "$spec" 2>/dev/null)" || fail 4 runtime-not-installed 'the selected mise SDK is absent; installation is a separate write'
if [ "$platform" = windows ]; then installed_dir="$(cygpath -u "$installed_dir")"; fi
[ -d "$installed_dir" ] || fail 4 runtime-not-installed 'the selected mise SDK directory is absent'
selected_python=python
if [ "$runtime" = python ]; then
    for python_entry in "$installed_dir/python.exe" "$installed_dir/bin/python" \
        "$installed_dir/bin/python3" "$installed_dir/bin/python${version%.*}"; do
        if [ -f "$python_entry" ] && [ -x "$python_entry" ]; then selected_python="$python_entry"; break; fi
    done
    # A Homebrew framework may expose only versioned executable names. Keep its
    # actual prefix and executable; verification still checks both provenance
    # and exact version. No alias or synthetic SDK directory is created.
    export KAI_PYTHON_BIN="$selected_python"
fi
if [ "$action" = exec ]; then
    shift 3
    [ "${1:-}" = -- ] || fail 2 usage 'exec requires -- COMMAND [ARG...]'
    shift; [ "$#" -gt 0 ] || fail 2 usage 'exec requires a command'
    if [ "$runtime:$1" = python:python ]; then shift; set -- "$selected_python" "$@"; fi
    exec "${mise_command[@]}" exec "$spec" -- "$@"
fi
validation=not-run; details='{}'
if [ "$action" = verify ] || [ "$action" = install ]; then
    check_root="$installed_dir"; check_here="$here"
    if [ "$platform" = windows ]; then
        check_root="$(cygpath -w "$installed_dir")"; check_here="$(cygpath -w "$here")"
    fi
    case "$runtime" in
        python)
            details="$("$mise" exec "$spec" -- "$selected_python" "$check_here/check-python.py" "$check_root" "$version")" || fail 11 runtime-verification-failed 'Python version, provenance or functional module check failed'
            "$mise" exec "$spec" -- "$selected_python" -m pip --version >&2 || fail 11 runtime-verification-failed 'selected Python pip is unavailable' ;;
        node)
            details="$("$mise" exec "$spec" -- node "$check_here/check-node.cjs" "$check_root" "$version")" || fail 11 runtime-verification-failed 'Node version, provenance or script check failed'
            if [ "$platform" = windows ]; then
                npm_cli="$installed_dir/node_modules/npm/bin/npm-cli.js"
                [ -f "$npm_cli" ] && [ ! -L "$npm_cli" ] || fail 11 runtime-verification-failed 'selected Windows Node npm entry is unavailable'
                "$mise" exec "$spec" -- node "$(cygpath -w "$npm_cli")" --version >&2 || fail 11 runtime-verification-failed 'selected Node npm is unavailable'
            else
                "$mise" exec "$spec" -- npm --version >&2 || fail 11 runtime-verification-failed 'selected Node npm is unavailable'
            fi ;;
        go)
            details="$("$mise" exec "$spec" -- go env -json GOROOT GOVERSION)" || fail 11 runtime-verification-failed 'selected Go environment query failed'
            [ "$(printf '%s' "$details" | jq -r .GOVERSION)" = "go$version" ] || fail 11 runtime-verification-failed 'Go version mismatch'
            go_root="$(printf '%s' "$details" | jq -r .GOROOT)"
            if [ "$platform" = windows ]; then go_root="$(cygpath -u "$go_root")"; fi
            [ "$(CDPATH= cd -- "$go_root" && pwd -P)" = "$(CDPATH= cd -- "$installed_dir" && pwd -P)" ] || fail 11 runtime-verification-failed 'Go SDK source does not match mise installation' ;;
    esac
    validation=passed
fi
if [ "$action" = install ]; then
    case "$scope" in
        project) "$mise" use --pin "$spec" >&2 || fail "$?" selection-failed 'project version selection failed' ;;
        global) "$mise" use --global --pin "$spec" >&2 || fail "$?" selection-failed 'explicit global selection failed' ;;
    esac
fi
jq -cn --arg spec "$spec" --arg root "$installed_dir" --arg action "$action" --arg scope "$scope" --arg validation "$validation" --argjson details "$details" \
    '{schemaVersion:1,status:"passed",operation:$action,spec:$spec,installRoot:$root,scope:$scope,runtimeValidation:$validation,details:$details,exitCode:0}'
