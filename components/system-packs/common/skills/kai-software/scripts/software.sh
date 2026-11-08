#!/usr/bin/env bash
set -eu
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
if [ "${1:-}" = task ];then shift;exec bash "$here/software-task.sh" "$@";fi
. "$here/../../kai-tool-bootstrap/scripts/jq-env.sh"
kai_use_jq full || exit $?
bootstrap="$here/../../kai-tool-bootstrap/scripts/tool.sh"
platform="${KAI_PLATFORM:-$(bash "$bootstrap" probe bash | jq -er .platform)}"
action="${1:-}"; subject="${2:-}"; requested="${3:-}"
cache="${KAI_SOFTWARE_CACHE:-$HOME/.cache/kai/software}"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
zsetup="${KAI_ZSETUP_BIN:-$(command -v zsetup 2>/dev/null || true)}"
if [ -z "$zsetup" ] && [ -x "$HOME/.local/bin/zsetup" ]; then zsetup="$HOME/.local/bin/zsetup"; fi

fail() {
    local code="$1" category="$2" detail="$3"
    jq -cn --arg category "$category" --arg detail "$detail" --argjson code "$code" \
        '{schemaVersion:1,status:"failed",category:$category,reason:$detail,exitCode:$code}'
    exit "$code"
}
case "$action" in search|info|install|download|remove|files|owner|refresh) ;; *) fail 2 usage 'software.sh search|info|install|download|remove|files|owner|refresh SUBJECT [VERSION]' ;; esac
if [ "$platform" = windows ]; then
    destination=; architecture="${KAI_WINGET_ARCH:-}"; policy="${KAI_SOFTWARE_ACCELERATION:-auto}"
    case "$policy" in required|auto|none) ;; *) fail 2 usage 'KAI_SOFTWARE_ACCELERATION must be required, auto or none on Windows' ;; esac
    if [ "$action" = download ]; then
        [ "$#" -ge 4 ] && [ "$#" -le 5 ] && [ -n "$requested" ] || fail 2 usage 'software.sh download winget:ID VERSION ABSOLUTE_DIRECTORY [ARCH]'
        destination="$4"; architecture="${5:-$architecture}"
        if command -v cygpath >/dev/null 2>&1; then destination="$(cygpath -w "$destination")"; fi
    fi
    case "$action" in
        search) provider="${KAI_SOFTWARE_PROVIDER:-all}" ;;
        refresh)
            case "$subject" in
                scoop:*) provider=scoop; subject="${subject#scoop:}" ;;
                winget:*) provider=winget; subject="${subject#winget:}" ;;
                *) fail 2 usage 'refresh requires scoop:BUCKET or winget:winget' ;;
            esac ;;
        owner) provider=winget ;;
        *)
            case "$subject" in
                winget:*) provider=winget; subject="${subject#winget:}" ;;
                scoop:*) provider=scoop; subject="${subject#scoop:}" ;;
                *) fail 2 usage 'use a source-qualified Windows software ID' ;;
            esac ;;
    esac
    case "$provider" in all|winget|scoop) ;; *) fail 18 unsupported-platform 'the selected provider has no Windows policy' ;; esac
    [ "$provider" != all ] || [ "$action" = search ] || fail 2 usage 'provider aggregation is read-only and only valid for search'
    [ "$provider" != scoop ] || [ "$action" != download ] || fail 18 unsupported-operation 'Scoop download seeds its managed cache and has no destination-directory contract'
    powershell="${KAI_POWERSHELL_BIN:-$(command -v pwsh.exe 2>/dev/null || command -v powershell.exe 2>/dev/null || true)}"
    if command -v cygpath >/dev/null 2>&1; then
        powershell="$(cygpath -u "$powershell")"
    fi
    [ -n "$powershell" ] && [ -x "$powershell" ] || fail 127 missing-executable 'an existing native PowerShell is required for structured WinGet operations'
    ks_cli="${KAI_KSCLI_BIN:-$(command -v ks-cli 2>/dev/null || command -v ks-cli.exe 2>/dev/null || true)}"
    zsetup_native="$zsetup"; scoop_root="${KAI_SCOOP_ROOT:-}"; runtime_binary="${KAI_KSPEEDER_RUNTIME_BINARY:-}"; runtime_identity="${KAI_KSPEEDER_RUNTIME_IDENTITY:-}"
    if command -v cygpath >/dev/null 2>&1; then
        [ -z "$ks_cli" ] || ks_cli="$(cygpath -w "$ks_cli")"
        [ -z "$zsetup_native" ] || zsetup_native="$(cygpath -w "$zsetup_native")"
        [ -z "$scoop_root" ] || scoop_root="$(cygpath -w "$scoop_root")"
        [ -z "$runtime_binary" ] || runtime_binary="$(cygpath -w "$runtime_binary")"
        [ -z "$runtime_identity" ] || runtime_identity="$(cygpath -w "$runtime_identity")"
    fi
    invoke_windows_provider() {
        local selected="$1" native_script request
        native_script="$here/$selected.ps1"
        if command -v cygpath >/dev/null 2>&1; then native_script="$(cygpath -w "$native_script")"; fi
        request="$(jq -cn --arg action "$action" --arg subject "$subject" --arg version "$requested" \
            --arg ksCli "$ks_cli" --arg zsetup "$zsetup_native" --arg architecture "$architecture" \
            --arg destination "$destination" --arg policy "$policy" --arg root "$scoop_root" \
            --arg runtimeBinary "$runtime_binary" --arg runtimeIdentity "$runtime_identity" \
            '{action:$action,subject:$subject,version:$version,ksCli:$ksCli,zsetup:$zsetup,architecture:$architecture,destination:$destination,policy:$policy,root:$root,runtimeBinary:$runtimeBinary,runtimeIdentity:$runtimeIdentity}')"
        printf '%s\n' "$request" | MSYS2_ARG_CONV_EXCL='*' "$powershell" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$native_script"
    }
    if [ "$provider" = all ]; then
        scoop_rows="$(invoke_windows_provider scoop)" || exit "$?"
        winget_rows="$(invoke_windows_provider winget)" || exit "$?"
        jq -cn --argjson scoop "$scoop_rows" --argjson winget "$winget_rows" \
            '$scoop + $winget | sort_by(if .source=="scoop" and .type=="cli-tool" then 0 elif .source=="winget" then 1 else 2 end, .id)'
        exit 0
    fi
    invoke_windows_provider "$provider"
    exit $?
fi
[ "$action" != download ] || fail 18 unsupported-operation 'prepared software download is currently available for the Windows winget provider'
native_provider() { case "$platform" in ubuntu|debian) echo apt ;; istoreos|openwrt) echo opkg ;; macos) echo brew ;; windows) echo winget ;; *) echo unknown ;; esac; }
validate_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || fail 2 usage 'invalid exact software name'; }
validate_provider() {
    case "$provider:$platform" in
        apt:ubuntu|apt:debian|opkg:istoreos|opkg:openwrt|istore:istoreos|istore:openwrt|zsetup:ubuntu|zsetup:debian|zsetup:linux|zsetup:istoreos|zsetup:openwrt|brew:macos|winget:windows) ;;
        *) fail 18 unsupported-platform 'provider is not registered for this target' ;;
    esac
}
compatible_application() {
    case "$provider:$platform" in
        zsetup:istoreos|zsetup:openwrt)
            # The portable Linkspace launcher explicitly supports Linux uname
            # and these architectures. Service/client integration keeps its
            # native OpenWrt package policy; do not enable other Linux installers.
            [ "$1" = linkspace ] || return 1
            case "${KAI_TARGET_ARCH:-$(uname -m)}" in x64|x86_64|amd64|arm64|aarch64|armv7|armv7l) return 0 ;; *) return 1 ;; esac ;;
        *) return 0 ;;
    esac
}
zconfig="$cache/zsetup-config.json"
cached_zsetup() {
    [ -n "$zsetup" ] || fail 127 missing-executable 'zsetup is required'
    [ -s "$zconfig" ] || fail 4 index-unavailable 'explicitly refresh the zsetup index first'
    ZSETUP_CONFIG="$zconfig" "$zsetup" "$@"
}

run_brew() {
    local client doctor code=0
    case "${KAI_SOFTWARE_ACCELERATION:-none}" in
        none) command brew "$@"; return $? ;;
        required) ;;
        *) echo 'KAI_SOFTWARE_ACCELERATION must be none or required for Homebrew' >&2; return 2 ;;
    esac
    client="${KAI_KSCLI_BIN:-$(type -P ks-cli 2>/dev/null || true)}"
    if [ -z "$client" ] || [ ! -x "$client" ]; then
        echo 'Homebrew acceleration requires an existing compatible ks-cli' >&2
        return 127
    fi
    doctor="$("$client" doctor brew --json)" || code=$?
    if [ "$code" != 0 ]; then printf '%s\n' "$doctor" >&2; return "$code"; fi
    if ! printf '%s' "$doctor" | jq -e '.schema_version==1 and .tool=="brew" and .overall=="pass"' >/dev/null; then
        printf '%s\n' "$doctor" >&2
        echo 'Homebrew acceleration readiness was not established' >&2
        return 11
    fi
    "$client" brew "$@"
}

if [ "$action" = refresh ]; then
    provider="$subject"; validate_provider
    code=0
    case "$provider" in
        apt) apt-get update >&2 || code=$? ;;
        opkg) opkg update >&2 || code=$? ;;
        istore) is-opkg update >&2 || code=$? ;;
        zsetup)
            [ -n "$zsetup" ] || fail 127 missing-executable 'zsetup is required'
            mkdir -p "$cache"
            candidate="$(mktemp "$cache/index.XXXXXX")"
            trap 'rm -f "$candidate"' EXIT
            "$zsetup" download -o "$candidate" --max-bytes 65536 --min-free-bytes 1048576 \
                --overall-timeout 120s https://fw.koolcenter.com/binary/zsetup/config.json >&2 || code=$?
            if [ "$code" = 0 ]; then
                jq -e '.schema_version == 1 and (.installers | type == "array")' "$candidate" >/dev/null || code=11
            fi
            if [ "$code" = 0 ]; then mv "$candidate" "$zconfig"; fi ;;
        brew) run_brew update >&2 || code=$? ;;
    esac
    [ "$code" = 0 ] || fail "$code" provider-failed 'explicit index refresh failed'
    jq -cn --arg provider "$provider" --arg time "$timestamp" '{schemaVersion:1,status:"passed",operation:"refresh",provider:$provider,evidenceTime:$time,exitCode:0}'
    exit 0
fi

package_info() {
    local available= installed= raw= entry= version= type=system-package manager="$provider"
    compatible_application "$name" || fail 18 unsupported-platform 'this installer is not mapped to the target and architecture; use its native package integration'
    case "$provider" in
        apt)
            raw="$(apt-cache policy "$name")" || fail "$?" provider-failed 'apt cache query failed'
            available="$(printf '%s\n' "$raw" | awk '/Candidate:/ {print $2; exit}')"
            [ "$available" != '(none)' ] || available=
            installed="$(dpkg-query -W '-f=${Status}\t${Version}\n' "$name" 2>/dev/null | awk -F '\t' '$1 == "install ok installed" {print $2}' || true)" ;;
        opkg|istore)
            if [ "$provider" = istore ]; then raw="$(is-opkg info "$name")" || fail "$?" provider-failed 'iStore cache query failed';
            else raw="$(opkg info "$name")" || fail "$?" provider-failed 'opkg cache query failed'; fi
            available="$(printf '%s\n' "$raw" | sed -n 's/^Version: //p' | head -n 1)"
            installed="$(opkg status "$name" 2>/dev/null | awk '/^Version:/ {v=$2} /^Status:.* installed$/ {print v}' || true)"
            if [ "$provider" = istore ]; then type=istore-package; fi ;;
        zsetup)
            raw="$(cached_zsetup install --list)" || fail "$?" provider-failed 'zsetup catalog query failed'
            printf '%s\n' "$raw" | grep -Fxq -- "$name" || fail 4 no-candidate 'software is absent from the cached authoritative catalog'
            type=internal-software
            # Query ownership/version metadata; never run a business command
            # merely to discover its version (some programs enter a menu).
            local prefix="${ZSETUP_INSTALL_PREFIX:-$HOME/.local/lib/linkease/$name}" pointer= selected=
            if [ -f "$prefix/.managed" ] && [ ! -L "$prefix/.managed" ] && \
               [ "$(head -c 65 "$prefix/.managed")" = "$name" ] && [ -L "$prefix/current" ]; then
                pointer="$(readlink "$prefix/current")"
                case "$pointer" in
                    versions/*/bin/"$name")
                        selected="${pointer#versions/}"; selected="${selected%/bin/"$name"}"
                        if [[ "$selected" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] && \
                           [ -x "$prefix/$pointer" ] && [ -L "$HOME/.local/bin/$name" ] && \
                           [ "$(readlink "$HOME/.local/bin/$name")" = "$prefix/current" ]; then installed="$selected"; fi ;;
                esac
            fi
            available= ;;
        brew)
            raw="$(run_brew info --json=v2 "$name")" || fail "$?" provider-failed 'Homebrew query failed'
            available="$(printf '%s' "$raw" | jq -r '.formulae[0].versions.stable // empty')"
            installed="$(printf '%s' "$raw" | jq -r '.formulae[0].installed[0].version // empty')" ;;
    esac
    [ -n "$available" ] || [ -n "$installed" ] || [ "$provider" = zsetup ] || fail 4 no-candidate 'no cached or installed candidate; explicitly refresh if needed'
    entry="$(command -v "$name" 2>/dev/null || true)"
    if [ -z "$entry" ] && [ -x "$HOME/.local/bin/$name" ]; then entry="$HOME/.local/bin/$name"; fi
    jq -cn --arg id "$provider:$name" --arg name "$name" --arg type "$type" --arg provider "$provider" \
        --arg platform "$platform" --arg available "$available" --arg installed "$installed" --arg entry "$entry" --arg time "$timestamp" \
        '{schemaVersion:1,id:$id,name:$name,type:$type,source:$provider,manager:$provider,platform:$platform,compatible:true,availableVersion:(if $available=="" then null else $available end),installedVersion:$installed,installed:($installed!=""),entrypoint:$entry,evidenceTime:$time}'
}

if [ "$action" = search ]; then
    [ -n "$subject" ] && [ "${subject#-}" = "$subject" ] || fail 2 usage 'a search term is required'
    provider="${KAI_SOFTWARE_PROVIDER:-$(native_provider)}"; validate_provider
    case "$provider" in
        apt) raw="$(apt-cache search --names-only -- "$subject")" || fail "$?" provider-failed 'apt search failed'; names="$(printf '%s\n' "$raw" | awk 'NF {print $1}')" ;;
        opkg) raw="$(opkg list)" || fail "$?" provider-failed 'opkg search failed'; names="$(printf '%s\n' "$raw" | grep -iF -- "$subject" | awk 'NF {print $1}' || true)" ;;
        istore) raw="$(is-opkg opkg list)" || fail "$?" provider-failed 'iStore search failed'; names="$(printf '%s\n' "$raw" | grep -iF -- "$subject" | awk 'NF {print $1}' || true)" ;;
        zsetup) raw="$(cached_zsetup install --list)" || fail "$?" provider-failed 'zsetup search failed'; names="$(printf '%s\n' "$raw" | grep -iF -- "$subject" || true)" ;;
        brew) names="$(run_brew search --formula -- "$subject")" || fail "$?" provider-failed 'Homebrew search failed' ;;
    esac
    names="$(while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        if compatible_application "$candidate"; then printf '%s\n' "$candidate"; fi
    done <<< "$names")"
    if printf '%s\n' "$names" | grep -Fxq -- "$subject"; then names="$subject";
    else names="$(printf '%s\n' "$names" | head -n 3)"; fi
    rows="$(while IFS= read -r name; do [ -n "$name" ] || continue; validate_name "$name"; package_info; done <<< "$names")"
    printf '%s\n' "$rows" | jq -s 'map(. + {matchReason:"matched in the selected provider catalog"})'
    exit 0
fi

if [ "$action" = owner ]; then
    case "$subject" in /*) ;; *) fail 2 usage 'owner requires an absolute path' ;; esac
    case "$(native_provider)" in apt) exec dpkg-query -S "$subject" ;; opkg) exec opkg search "$subject" ;; *) fail 18 unsupported-operation 'use the native provider file-ownership query' ;; esac
fi

case "$subject" in *:*) provider="${subject%%:*}"; name="${subject#*:}" ;; *) fail 2 usage 'use a source-qualified software ID' ;; esac
validate_name "$name"; validate_provider
compatible_application "$name" || fail 18 unsupported-platform 'this installer is not mapped to the target and architecture; use its native package integration'
if [ "$action" = info ]; then package_info; exit 0; fi
if [ "$action" = files ]; then
    case "$provider" in apt) exec dpkg-query -L "$name" ;; opkg|istore) exec opkg files "$name" ;; brew) exec brew list "$name" ;; *) fail 18 unsupported-operation 'the provider has no file-list API' ;; esac
fi
if [ "$action" = remove ] && [ "$provider" = zsetup ]; then
    [ -n "$zsetup" ] || fail 127 missing-executable 'an existing canonical zsetup is required for owner removal'
    resource="$here/../resources/remove-managed.sh"
    lock="$here/../resources/owner.lock.json"
    jq -e --arg app "$name" '.protocol == "managed-binary-remove-v1" and (.applications | index($app) != null)' "$lock" >/dev/null || fail 18 unsupported-operation 'owner removal supports managed binary clients only'
    expected="$(jq -er .sha256 "$lock")"
    actual="$(sha256sum "$resource")" || fail 127 missing-executable 'sha256sum is required for owner resource verification'
    [ "${actual%% *}" = "$expected" ] || fail 11 integrity-failed 'owner removal resource digest mismatch'
    code=0
    ZSETUP_BIN="$zsetup" "$zsetup" run -- sh "$resource" "$name" >&2 || code=$?
    [ "$code" = 0 ] || fail "$code" owner-removal-failed 'owner preserved conflicting or modified files; inspect original stderr'
    jq -cn --arg id "$subject" '{schemaVersion:1,status:"passed",operation:"remove",id:$id,preserved:["config","data","cache"],exitCode:0}'
    exit 0
fi
if [ "$action" = install ]; then
    info="$(package_info)" || exit "$?"
    if [ -n "$requested" ] && [ "$provider" != zsetup ] && [ "$(printf '%s' "$info" | jq -r .availableVersion)" != "$requested" ]; then
        fail 4 version-unavailable 'requested exact version differs from the current cached candidate'
    fi
    if [ "$provider" = zsetup ] && [ -n "$requested" ]; then fail 18 unsupported-operation 'this installer resolves its own product version; no exact-version API is published'; fi
fi
code=0
case "$action:$provider" in
    install:apt)
        package="$name"; [ -z "$requested" ] || package="$name=$requested"
        DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::=--force-confold -- "$package" >&2 || code=$? ;;
    remove:apt) DEBIAN_FRONTEND=noninteractive apt-get remove -y -- "$name" >&2 || code=$? ;;
    install:opkg) opkg install "$name" >&2 || code=$? ;;
    remove:opkg) opkg remove "$name" >&2 || code=$? ;;
    install:istore) is-opkg install "$name" >&2 || code=$? ;;
    remove:istore) is-opkg remove "$name" >&2 || code=$? ;;
    install:zsetup) cached_zsetup install "$name" --foreground >&2 || code=$? ;;
    install:brew) run_brew install "$name" >&2 || code=$? ;;
    remove:brew) brew uninstall "$name" >&2 || code=$? ;;
    *) fail 18 unsupported-operation 'provider lifecycle adapter is unavailable' ;;
esac
[ "$code" = 0 ] || fail "$code" provider-failed 'native package operation failed; inspect its original stderr'
if [ "$action" = install ]; then
    result="$(package_info)" || exit "$?"
    [ -z "$requested" ] || [ "$(printf '%s' "$result" | jq -r .installedVersion)" = "$requested" ] || fail 11 version-mismatch 'installed version differs from the selected version'
    printf '%s\n' "$result"
else
    jq -cn --arg id "$subject" '{schemaVersion:1,status:"passed",operation:"remove",id:$id,exitCode:0}'
fi
