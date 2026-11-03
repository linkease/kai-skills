#!/usr/bin/env bash
set -eu
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
. "$here/../resources/runtime/kai-tool-bootstrap/scripts/jq-env.sh"
kai_use_jq full || exit $?
runtime_helper="$here/../resources/runtime/kai-dev-environment/scripts/runtime.sh"
fail() { jq -cn --arg category "$2" --arg reason "$3" --argjson code "$1" '{schemaVersion:1,status:"failed",category:$category,reason:$reason,exitCode:$code}'; exit "$1"; }
action="${1:-}"; manager="${2:-}"; version="${3:-}"; project="${4:-}"
case "$action" in install|run|add|sources) ;; *) fail 2 usage 'dependencies.sh install|run|add|sources npm|pip|uv|go EXACT_RUNTIME_VERSION PROJECT [-- ARGS...]' ;; esac
case "$manager" in npm) runtime=node ;; pip|uv) runtime=python ;; go) runtime=go ;; *) fail 2 usage 'unsupported project dependency manager' ;; esac
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 2 version-selection 'a complete runtime version is required'
[ -d "$project" ] || fail 4 project-unavailable 'project directory must already exist'
project="$(CDPATH= cd -- "$project" && pwd -P)"
if [ "$action" = sources ] && [ "$manager" = npm ]; then
    [ -f "$project/package.json" ] || fail 4 manifest-required 'source inspection requires package.json'
    json_files=("$project/package.json")
    [ ! -f "$project/package-lock.json" ] || json_files+=("$project/package-lock.json")
    jq -s '
      def kind:
        if test("^(git[+:]|ssh:|github:|gitlab:|bitbucket:)") then "git"
        elif test("^(file:|link:|workspace:|\\./|\\.\\./)") then "local"
        elif test("^https://registry.npmjs.org/") then "registry"
        elif test("^https?://") then "url"
        elif test("^[^@ /]+/[^ /]+") then "git" else "registry" end;
      .[0] as $manifest | (.[1] // {}) as $lock | $manifest |
      {schemaVersion:1,accelerationValidation:"not-tested",privateRegistryPolicy:"requires-separate-review",
       sources: (((.dependencies // {}) + (.devDependencies // {}) + (.optionalDependencies // {})) | to_entries |
        map(. as $entry | {name:.key,type:(($lock.packages["node_modules/" + $entry.key].resolved // $entry.value) | tostring | kind)}))}
    ' "${json_files[@]}" || fail 4 invalid-manifest 'cannot inspect the npm manifest or lock'
    exit 0
fi
if [ "$action" = sources ]; then
    source_files=()
    case "$manager" in
        pip) candidates=(requirements.txt) ;;
        uv) candidates=(requirements.txt pyproject.toml uv.lock) ;;
        go) candidates=(go.mod) ;;
    esac
    for candidate in "${candidates[@]}"; do
        [ ! -f "$project/$candidate" ] || source_files+=("$project/$candidate")
    done
    [ "${#source_files[@]}" -gt 0 ] || fail 4 manifest-required 'no supported project metadata was found for source inspection'
    source_rows="$(awk -v manager="$manager" '
      /^[[:space:]]*(#|$)/ {next}
      {
        kind="registry"
        if (manager == "go") {
          if ($0 ~ /^[[:space:]]*(module |go |toolchain |[()])/) next
          kind="module-proxy"
          if ($0 ~ /=>[[:space:]]*(\.\.?\/|\/)/) kind="local"
        } else {
          if ($0 ~ /^[[:space:]]*--hash=/) next
          if (FILENAME !~ /requirements.txt$/) kind="project-metadata"
          if ($0 ~ /(git\+|git:\/\/|git[[:space:]]*=|ssh:\/\/)/) kind="git"
          else if ($0 ~ /https?:\/\//) kind="url"
          else if ($0 ~ /(file:|path[[:space:]]*=|^[[:space:]]*\.\.?\/)/) kind="local"
          else if ($0 ~ /^[[:space:]]*(-r|-c|--requirement|--constraint)/) kind="include"
          if (kind == "project-metadata") next
        }
        name=FILENAME; sub(/^.*\//,"",name)
        printf "%s:%d\t%s\n",name,FNR,kind
      }' "${source_files[@]}")" || fail 4 source-unreadable 'cannot inspect the existing source metadata'
    printf '%s\n' "$source_rows" | jq -Rsc '{schemaVersion:1,requiresSourceReview:true,accelerationValidation:"not-tested",sources:(split("\n")|map(select(length>0)|split("\t")|{name:.[0],type:.[1]}))}'
    exit 0
fi
if [ "${KAI_DEP_ENTERED:-0}" != 1 ]; then
    probe_code=0
    probe="$(bash "$runtime_helper" probe "$runtime" "$version")" || probe_code=$?
    if [ "$probe_code" != 0 ]; then printf '%s\n' "$probe"; exit "$probe_code"; fi
    sdk_root="$(printf '%s' "$probe" | jq -er .installRoot)"
    exec bash "$runtime_helper" exec "$runtime" "$version" -- env KAI_DEP_ENTERED=1 KAI_DEP_SDK_ROOT="$sdk_root" bash "$here/dependencies.sh" "$@"
fi
cd -- "$project"
platform="${KAI_PLATFORM:-$(bash "$here/../resources/runtime/kai-tool-bootstrap/scripts/tool.sh" probe bash | jq -er .platform)}"
npm_native=(npm)
if [ "$platform:$manager" = windows:npm ]; then
    sdk="$(CDPATH= cd -- "${KAI_DEP_SDK_ROOT:?selected SDK root is required}" && pwd -P)"
    node="$sdk/node.exe"; npm_cli="$sdk/node_modules/npm/bin/npm-cli.js"
    [ -f "$node" ] && [ -x "$node" ] && [ ! -L "$node" ] && [ -f "$npm_cli" ] && [ ! -L "$npm_cli" ] || fail 4 tool-provenance-mismatch 'the selected Windows Node SDK has no native Node/npm entry'
    npm_parent="$(CDPATH= cd -- "$(dirname "$npm_cli")" && pwd -P)"
    case "$npm_parent" in "$sdk"/*) ;; *) fail 4 tool-provenance-mismatch 'the npm entry leaves the selected Node SDK' ;; esac
    npm_native=(env 'MSYS2_ARG_CONV_EXCL=*' "$node" "$(cygpath -w "$npm_cli")")
fi
hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1";
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1";
    else fail 127 missing-executable 'SHA256 support is required to check project locks'; fi
}
prepare_command() {
    native_command=("$manager")
    if [ "$manager" = npm ]; then native_command=("${npm_native[@]}"); fi
    if [ "$manager" = pip ]; then native_command=("$venv_python" -m pip); fi
    if [ "$platform:$manager" = windows:pip ]; then native_command=(env 'MSYS2_ARG_CONV_EXCL=*' "$venv_python" -m pip); fi
    case "${KAI_DEP_ACCELERATION:-none}" in
        none) ;;
        required)
            local client doctor code
            client="${KAI_KSCLI_BIN:-$(command -v ks-cli 2>/dev/null || true)}"
            [ -n "$client" ] || { [ ! -x "$HOME/.local/bin/ks-cli" ] || client="$HOME/.local/bin/ks-cli"; }
            [ -n "$client" ] && [ -x "$client" ] || fail 127 missing-executable 'explicit acceleration requires an existing ks-cli'
            code=0; doctor="$("$client" doctor "$manager" --json)" || code=$?
            [ "$code" = 0 ] || fail "$code" acceleration-unavailable 'read-only ks-cli doctor failed; inspect the existing gateway without installing or starting a service'
            printf '%s' "$doctor" | jq -e --arg tool "$manager" '.schema_version == 1 and .overall == "pass" and .tool == $tool' >/dev/null || fail 4 acceleration-unavailable 'ks-cli doctor did not confirm this tool is ready'
            if [ "$platform" = windows ] && { [ "$manager" = npm ] || [ "$manager" = pip ]; }; then
                # Native Windows npm.cmd needs a command processor. Execute the
                # SDK's node.exe/npm JS (or venv Python -m pip) instead, applying
                # only the existing client's public, validated network plan.
                local plan key endpoint
                key=npm_config_registry
                [ "$manager" != pip ] || key=PIP_INDEX_URL
                code=0; plan="$("$client" --explain --json "$manager")" || code=$?
                [ "$code" = 0 ] || fail "$code" acceleration-unavailable 'cannot read the native package network plan'
                printf '%s' "$plan" | jq -e --arg tool "$manager" --arg key "$key" '
                  .schema_version == 1 and .command == [$tool] and
                  (.environment|type == "object" and keys == [$key]) and
                  (.environment[$key]|type == "string" and
                    (if $tool == "npm" then test("^https://dl-npm\\.linkease\\.net:[0-9]+/?$")
                     else test("^https://dl-pypi\\.linkease\\.net:[0-9]+/simple/$") end))
                ' >/dev/null || fail 4 acceleration-unavailable 'unsupported native package environment plan'
                endpoint="$(printf '%s' "$plan" | jq -er --arg key "$key" '.environment[$key]')"
                export "$key=$endpoint"
            else
                native_command=("$client" "$manager")
            fi ;;
        *) fail 2 usage 'KAI_DEP_ACCELERATION must be none or required' ;;
    esac
}
prepare_venv() {
    local code venv_path check_venv check_sdk
    venv_path="$project/.venv"
    [ ! -L "$venv_path" ] || fail 4 venv-conflict 'the project venv is an external link; preserve it'
    if [ ! -e "$venv_path" ]; then
        [ "$action" = install ] || fail 4 venv-unavailable 'install the project environment before running its dependency tool'
        code=0; "${KAI_PYTHON_BIN:-python}" -m venv "$venv_path" >&2 || code=$?
        [ "$code" = 0 ] || fail "$code" venv-creation-failed 'the selected Python could not create this project venv; inspect any partial directory'
    fi
    [ -f "$venv_path/pyvenv.cfg" ] || fail 4 venv-conflict 'the existing venv is incomplete or externally managed; preserve it'
    check_venv="$venv_path"; check_sdk="${KAI_DEP_SDK_ROOT:?selected SDK root is required}"
    if [ -x "$venv_path/Scripts/python.exe" ]; then
        venv_python="$venv_path/Scripts/python.exe"
        check_venv="$(cygpath -w "$venv_path")"; check_sdk="$(cygpath -w "$check_sdk")"
        export PATH="$venv_path/Scripts:$PATH" VIRTUAL_ENV="$check_venv"
    else
        venv_python="$venv_path/bin/python"
        export PATH="$venv_path/bin:$PATH" VIRTUAL_ENV="$venv_path"
    fi
    [ -x "$venv_python" ] || fail 4 venv-conflict 'the existing project venv has no usable interpreter'
    "$venv_python" -c 'import pathlib,sys; assert sys.prefix != sys.base_prefix; assert pathlib.Path(sys.prefix).resolve() == pathlib.Path(sys.argv[1]).resolve(); assert pathlib.Path(sys.base_prefix).resolve() == pathlib.Path(sys.argv[2]).resolve(); assert sys.version.split()[0] == sys.argv[3]' "$check_venv" "$check_sdk" "$version" || fail 4 venv-conflict 'the existing venv belongs to a different Python; preserve it'
}
case "$manager" in
    npm)
        [ -f package.json ] || fail 4 manifest-required 'package.json is required'
        declared="$(jq -er '.packageManager // "npm"' package.json)" || fail 4 invalid-manifest 'cannot read package.json'
        case "$declared" in npm|npm@*) ;; *) fail 4 manager-mismatch 'preserve the existing package manager and lock format' ;; esac
        [ "${NODE_TLS_REJECT_UNAUTHORIZED:-1}" != 0 ] && [ "$("${npm_native[@]}" config get strict-ssl)" = true ] || fail 4 integrity-disabled 'npm TLS verification must remain enabled'
        prepare_command
        case "$action" in
            run|add)
                shift 4; [ "${1:-}" = -- ] || fail 2 usage 'native commands and explicit additions require -- ARGS'
                shift; [ "$#" -gt 0 ] || fail 2 usage 'native arguments are required'
                if [ "$action" = run ]; then exec "${native_command[@]}" "$@"; fi
                for package in "$@"; do case "$package" in -*) fail 2 usage 'add accepts dependency specifications, not npm options' ;; esac; done
                code=0; "${native_command[@]}" install --save-exact "$@" >&2 || code=$? ;;
            install)
                [ "$#" = 4 ] || fail 2 usage 'install uses the existing project lock; native options belong to run'
                [ -f package-lock.json ] || fail 4 lock-required 'npm requires its existing lock; use an explicit add operation to change dependencies'
                before="$(hash_file package-lock.json)"
                code=0; "${native_command[@]}" ci >&2 || code=$?
                if [ "$code" = 0 ]; then
                    [ "$(hash_file package-lock.json)" = "$before" ] || fail 11 lock-drift 'the existing lock changed; inspect the preserved files'
                fi ;;
        esac
        [ "$code" = 0 ] || fail "$code" native-dependency-failed 'npm failed; preserve its stderr and inspect the project lock and native package requirements'
        ;;
    uv)
        uv_version="${KAI_UV_VERSION:-}"
        [[ "$uv_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 4 tool-version-required 'select an exact installed uv version with KAI_UV_VERSION'
        mise="${KAI_MISE_BIN:-$(command -v mise 2>/dev/null || true)}"
        [ -n "$mise" ] || mise="$HOME/.local/bin/mise"
        uv_root="$("$mise" where "uv@$uv_version" 2>/dev/null)" || fail 4 tool-not-installed 'install the selected uv with mise in this runtime environment before dependency operations'
        if [ "${KAI_DEP_UV_ENTERED:-0}" != 1 ]; then
            exec "$mise" exec "python@$version" "uv@$uv_version" -- env KAI_DEP_UV_ENTERED=1 bash "$here/dependencies.sh" "$@"
        fi
        uv_executable="$(command -v uv 2>/dev/null || true)"
        [ -n "$uv_executable" ] || fail 127 missing-executable 'selected mise uv is absent from PATH'
        python -c 'from pathlib import Path; import sys; assert Path(sys.argv[1]).resolve() in Path(sys.argv[2]).resolve().parents' "$uv_root" "$uv_executable" || fail 4 tool-provenance-mismatch 'uv executable is outside the selected mise installation'
        uv_actual="$(uv --version)" || fail 4 tool-verification-failed 'selected uv is not executable'
        case "$uv_actual" in "uv $uv_version"|"uv $uv_version "*) ;; *) fail 4 tool-verification-failed 'selected uv version differs from the requested version' ;; esac
        [ -z "${UV_INSECURE_HOST:-}" ] || fail 4 integrity-disabled 'uv insecure-host bypass must not be enabled'
        [ "$action" != add ] || fail 2 usage 'use run -- add for an explicit uv project modification'
        lock=uv.lock
        if [ "$action" = install ]; then
            [ "$#" = 4 ] || fail 2 usage 'install uses the existing project lock'
            if [ -f uv.lock ]; then
                [ -f pyproject.toml ] || fail 4 manifest-required 'uv.lock requires pyproject.toml'
            else
                [ -f requirements.txt ] || fail 4 lock-required 'uv requires its existing uv.lock or requirements.txt; no implicit project conversion'
                lock=requirements.txt
            fi
        fi
        prepare_venv
        export UV_PYTHON_DOWNLOADS=never
        prepare_command
        if [ "$action" = run ]; then
            shift 4; [ "${1:-}" = -- ] || fail 2 usage 'native commands require -- ARGS'
            shift; [ "$#" -gt 0 ] || fail 2 usage 'native arguments are required'
            exec "${native_command[@]}" "$@"
        fi
        before="$(hash_file "$lock")"
        code=0
        if [ "$lock" = uv.lock ]; then
            "${native_command[@]}" sync --frozen --python "$venv_python" >&2 || code=$?
        else
            "${native_command[@]}" pip install --python "$venv_python" -r requirements.txt >&2 || code=$?
        fi
        [ "$code" = 0 ] || fail "$code" native-dependency-failed 'uv failed; preserve original stderr and inspect Python, lock or native-library requirements'
        [ "$(hash_file "$lock")" = "$before" ] || fail 11 lock-drift 'the existing uv lock changed; inspect the preserved files'
        ;;
    pip)
        [ "$action" != add ] || fail 2 usage 'use the existing Python project lock workflow for additions; no implicit requirements conversion'
        if [ "$action" = install ]; then
            [ "$#" = 4 ] && [ -f requirements.txt ] || fail 4 manifest-required 'pip install requires the existing requirements.txt'
        fi
        prepare_venv
        [ -z "${PIP_TRUSTED_HOST:-}" ] || fail 4 integrity-disabled 'pip trusted-host bypass must not be enabled'
        for key in global.trusted-host install.trusted-host; do
            trusted="$("$venv_python" -m pip config get "$key" 2>/dev/null || true)"
            [ -z "$trusted" ] || fail 4 integrity-disabled 'pip configuration contains a trusted-host bypass; preserve and inspect it'
        done
        prepare_command
        if [ "$action" = run ]; then
            shift 4; [ "${1:-}" = -- ] || fail 2 usage 'native commands require -- ARGS'
            shift; [ "$#" -gt 0 ] || fail 2 usage 'native arguments are required'
            exec "${native_command[@]}" "$@"
        fi
        before="$(hash_file requirements.txt)"
        code=0; "${native_command[@]}" install -r requirements.txt >&2 || code=$?
        [ "$code" = 0 ] || fail "$code" native-dependency-failed 'pip failed; preserve original stderr and inspect network, lock or native-library requirements'
        [ "$(hash_file requirements.txt)" = "$before" ] || fail 11 lock-drift 'the existing requirements changed; inspect the preserved files'
        ;;
    go)
        [ -f go.mod ] || fail 4 manifest-required 'Go operations require the existing go.mod'
        sumdb="$(go env GOSUMDB)"; insecure="$(go env GOINSECURE)"
        [ -n "$sumdb" ] && [ "$sumdb" != off ] && [ -z "$insecure" ] || fail 4 integrity-disabled 'Go checksum verification and TLS must remain enabled'
        export GOTOOLCHAIN=local
        prepare_command
        case "$action" in
            run|add)
                shift 4; [ "${1:-}" = -- ] || fail 2 usage 'native commands and explicit additions require -- ARGS'
                shift; [ "$#" -gt 0 ] || fail 2 usage 'native arguments are required'
                if [ "$action" = run ]; then exec "${native_command[@]}" "$@"; fi
                for module in "$@"; do case "$module" in -*) fail 2 usage 'add accepts module specifications, not Go options' ;; esac; done
                code=0; "${native_command[@]}" get "$@" >&2 || code=$? ;;
            install)
                [ "$#" = 4 ] || fail 2 usage 'install uses the existing Go project files'
                before=; [ ! -f go.sum ] || before="$(hash_file go.sum)"
                code=0; "${native_command[@]}" mod download >&2 || code=$?
                if [ "$code" = 0 ]; then "${native_command[@]}" mod verify >&2 || code=$?; fi
                if [ "$code" = 0 ] && [ -n "$before" ]; then
                    [ "$(hash_file go.sum)" = "$before" ] || fail 11 lock-drift 'the existing go.sum changed; inspect the preserved files'
                fi ;;
        esac
        [ "$code" = 0 ] || fail "$code" native-dependency-failed 'Go failed; preserve original stderr and inspect the module source or native requirements'
        ;;
esac
jq -cn --arg manager "$manager" --arg version "$version" --arg project "$project" --arg action "$action" \
    '{schemaVersion:1,status:"passed",operation:$action,manager:$manager,runtimeVersion:$version,project:$project,functionalValidation:"not-run",exitCode:0}'
