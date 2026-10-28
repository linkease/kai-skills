#!/usr/bin/env bash
# Bash 3.2 compatible. Native Windows first-time Bash is bootstrapped separately.
set -eu
here="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
action="${1:-}"; tool="${2:-}"
if [ "$tool" = jq ]; then exec bash "$here/jq.sh" "$action"; fi
case "$action" in probe|plan|ensure) ;; *) echo 'usage: tool.sh probe|plan|ensure bash|zsetup|mise|ks-cli' >&2; exit 2 ;; esac
case "$tool" in bash|zsetup|mise|ks-cli) ;; *) echo 'unsupported tool' >&2; exit 2 ;; esac
. "$here/jq-env.sh"
kai_use_jq basic || exit $?

detect_platform() {
    case "$(uname -s)" in
        Darwin) printf macos ;;
        MINGW*|MSYS*|CYGWIN*) printf windows ;;
        Linux)
            local id
            id="$(sed -n 's/^ID=//p' /etc/os-release 2>/dev/null | tr -d '\042\047')"
            case "$id" in istoreos|openwrt|ubuntu|debian) printf '%s' "$id" ;; *) printf linux ;; esac ;;
        *) printf unknown ;;
    esac
}
platform="${KAI_PLATFORM:-$(detect_platform)}"
trusted_path="${KAI_TRUSTED_TOOL_PATH:-}"
if [ "$platform" = windows ] && [ -n "$trusted_path" ] && command -v cygpath >/dev/null 2>&1; then
    trusted_path="$(cygpath -u "$trusted_path")"
fi
work="${KAI_TOOL_WORK_DIR:-$HOME/.local/share/kai/bootstrap}"
path=; version=; owner=unknown; status=missing; reason=; next=; commands='[]'; provider_result=null
case "$tool" in bash) minimum=3.2.0 ;; zsetup) minimum=0.5.0 ;; mise) minimum=2025.1.0 ;; ks-cli) minimum=0.8.5 ;; esac
if [ "$tool" = zsetup ] && { [ "$platform" = windows ] || [ "$platform" = macos ]; }; then minimum=0.4.0; fi

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1";
    else shasum -a 256 "$1"; fi
}
check_hash() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum -c "$1";
    else shasum -a 256 -c "$1"; fi
}

version_at_least() {
    local actual="$1" required="$2" a b i
    for i in 1 2 3; do
        a="${actual%%.*}"; b="${required%%.*}"
        case "$a:$b" in *[!0-9:]*|:*|*:) return 1 ;; esac
        [ "$a" -ge "$b" ] || return 1
        [ "$a" -le "$b" ] || return 0
        if [ "$actual" = "${actual#*.}" ]; then actual=0; else actual="${actual#*.}"; fi
        if [ "$required" = "${required#*.}" ]; then required=0; else required="${required#*.}"; fi
    done
}

apt_owns() {
    case "$platform" in ubuntu|debian|linux) ;; *) return 1 ;; esac
    command -v dpkg-query >/dev/null 2>&1 || return 1
    if dpkg-query -S "$1" >/dev/null 2>&1; then return 0; fi
    # Debian's merged-/usr image may retain /bin/bash in the package database.
    local alias
    case "$1" in /usr/bin/*) alias="/bin/${1##*/}" ;; /usr/sbin/*) alias="/sbin/${1##*/}" ;; *) return 1 ;; esac
    [ "$1" -ef "$alias" ] && dpkg-query -S "$alias" >/dev/null 2>&1
}

brew_owns() {
    [ "$platform" = macos ] && command -v brew >/dev/null 2>&1 || return 1
    local prefix
    prefix="$(brew --prefix "$tool" 2>/dev/null)" || return 1
    [ "$path" -ef "$prefix/bin/$tool" ]
}

discover() {
    local cache_verified= cache_version= release_lock= cache_arch= cached= expected= actual_digest=
    local mise_verified= native_plan= native_code=0
    path="$(command -v "$tool" 2>/dev/null || true)"
    if [ -z "$path" ] && [ -x "$HOME/.local/bin/$tool" ]; then path="$HOME/.local/bin/$tool"; fi
    if [ -z "$path" ] && [ "$platform" = windows ] && [ -x "$HOME/.local/bin/$tool.exe" ]; then path="$HOME/.local/bin/$tool.exe"; fi
    if [ "$tool" = zsetup ] && [ -n "${KAI_ZSETUP_BIN:-}" ]; then path="$KAI_ZSETUP_BIN"; fi
    if [ -n "$trusted_path" ]; then path="$trusted_path"; fi
    # The jq owner's first-time bootstrap intentionally leaves its core in
    # its rescue cache. Discover that exact existing release without creating
    # a launcher or executing a changed cache entry.
    if [ "$tool" = zsetup ] && [ -z "$path" ] && [ -z "$trusted_path" ]; then
        case "$platform:$(uname -s)" in ubuntu:Linux|debian:Linux|linux:Linux|istoreos:Linux|openwrt:Linux)
            case "$(uname -m)" in x86_64|amd64) cache_arch=x86_64 ;; aarch64|arm64) cache_arch=aarch64 ;; armv7|armv7l) cache_arch=armv7 ;; esac
            release_lock="${KAI_BOOTSTRAP_RELEASE_LOCK:-$here/../references/tools.lock.json}"
            cache_version="$(jq -er '.zsetup.version // empty' "$release_lock" 2>/dev/null)" || cache_version=
            expected="$(jq -er --arg arch "$cache_arch" '.zsetup.artifacts[$arch].sha256 // empty' "$release_lock" 2>/dev/null)" || expected=
            if [[ "$cache_version" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] && [[ "$expected" =~ ^[a-f0-9]{64}$ ]]; then
                cached="${ZSETUP_ROOT:-/tmp/zsetup}/rescue/$cache_version/zsetup"
                if [ -f "$cached" ] && [ -x "$cached" ]; then
                    path="$cached"; owner=zsetup-bootstrap-cache
                    actual_digest="$(hash_file "$cached")" || actual_digest=
                    if [ -L "$cached" ] || [ "${actual_digest%% *}" != "$expected" ]; then
                        status=conflict; reason='the owner bootstrap cache differs from its frozen artifact digest'; next='preserve the cache and inspect its original owner'; return
                    fi
                    cache_verified=1
                fi
            fi ;;
        esac
    fi
    [ -n "$path" ] && [ -x "$path" ] || { path=; status=missing; return; }
    # The Windows distribution has a companion executable. Validate the complete
    # owned installation before executing its main program, including on reuse.
    if [ "$tool" = mise ] && [ "$platform" = windows ] &&
       [ "$path" -ef "$HOME/.local/bin/mise.exe" ] &&
       [ -f "$HOME/.local/bin/mise.kai-bootstrap.json" ]; then
        release_lock="${KAI_BOOTSTRAP_RELEASE_LOCK:-$here/../references/tools.lock.json}"
        native_plan="$(powershell.exe -NoLogo -NoProfile -NonInteractive -File \
            "$(cygpath -w "$here/install-mise-windows.ps1")" -Action Plan \
            -Destination "$(cygpath -w "$HOME/.local/bin/mise.exe")" \
            -ReleaseLock "$(cygpath -w "$release_lock")")" || native_code=$?
        if [ "$native_code" != 0 ] || ! printf '%s' "$native_plan" | jq -e '.status == "reused"' >/dev/null; then
            status=conflict; owner=kai-bootstrap; reason='the managed Windows mise installation differs from its ownership receipt'; next='preserve both executables and inspect the original bootstrap owner'; return
        fi
        mise_verified=1
    fi
    local raw
    if [ "$tool" = bash ]; then raw="$("$path" -c 'printf %s "$BASH_VERSION"' 2>/dev/null || true)";
    else raw="$("$path" --version 2>/dev/null | head -n 1 || true)"; fi
    version="$(printf '%s\n' "$raw" | sed -n 's/^[^0-9]*\([0-9][0-9.]*\).*/\1/p')"
    owner=external
    if [ "$cache_verified" = 1 ]; then
        owner=zsetup-bootstrap-cache
        if [ "$raw" != "zsetup $cache_version" ]; then status=conflict; reason='the cached core reports a different release'; next='inspect the original bootstrap owner'; return; fi
    elif [ "$mise_verified" = 1 ]; then owner=kai-bootstrap
    elif [ "$path" = "$trusted_path" ] || { [ "$tool" = zsetup ] && [ "$path" = "${KAI_ZSETUP_BIN:-}" ]; }; then owner=trusted-existing
    elif apt_owns "$path"; then owner=apt
    elif { [ "$platform" = istoreos ] || [ "$platform" = openwrt ]; } && opkg search "$path" 2>/dev/null | grep -q .; then owner=opkg
    elif [ "$platform" = macos ] && [ "$path" = /bin/bash ]; then owner=apple
    elif brew_owns; then owner=homebrew
    elif [ "$platform" = windows ] && [ -n "${MSYSTEM:-}" ] && [ "$tool" = bash ] && [ "$path" -ef "$BASH" ]; then owner=msys
    elif [ -f "$HOME/.local/share/kai/tools/$tool.sha256" ] && check_hash "$HOME/.local/share/kai/tools/$tool.sha256" >/dev/null 2>&1; then owner=kai-bootstrap
    elif [ "$tool" = ks-cli ] && [ -L "$path" ]; then
        case "$(readlink "$path")" in "$HOME/.local/lib/linkease/ks-cli/"*) owner=zsetup ;; esac
    fi
    if [ "$owner" = external ]; then status=conflict; reason='existing executable has an external owner'; next='reuse its original manager or explicitly select a trusted compatible executable'
    elif version_at_least "$version" "$minimum"; then status=reused
    elif [ "$owner" = trusted-existing ]; then status=conflict; reason='existing external tool is too old'; next='upgrade with its original manager'
    else status=upgrade-needed; fi
}

array() { jq -cn --args '$ARGS.positional' -- "$@"; }
provider() {
    case "$platform:$tool" in
        istoreos:ks-cli|openwrt:ks-cli) commands="$(jq -cn '[ ["is-opkg","install","ks-cli"] ]')" ;;
        istoreos:mise|openwrt:mise) commands='[["is-opkg","install","mise"]]' ;;
        istoreos:bash|openwrt:bash) commands='[["opkg","install","bash"]]' ;;
        ubuntu:ks-cli|debian:ks-cli|linux:ks-cli) commands='[["zsetup","install","ks-cli","--foreground"]]' ;;
        ubuntu:zsetup|debian:zsetup|linux:zsetup|istoreos:zsetup|openwrt:zsetup) commands="[$(array bash "$here/bootstrap-core.sh")]" ;;
        ubuntu:mise|debian:mise|linux:mise|windows:mise) commands="[$(array bash "$here/install-mise.sh")]" ;;
        macos:mise) commands='[["brew","install","mise"]]' ;;
        ubuntu:bash|debian:bash) commands='[["apt-get","install","-y","bash"]]' ;;
        macos:bash) commands='[["brew","install","bash"]]' ;;
        *) status=unavailable; reason='no verified installer artifact is registered for this tool and platform'; next='reuse a trusted installed tool or publish the native artifact with version and SHA256'; commands='[]' ;;
    esac
}

emit() {
    jq -cn --arg tool "$tool" --arg platform "$platform" --arg status "$status" --arg path "$path" \
        --arg version "$version" --arg minimum "$minimum" --arg owner "$owner" --arg reason "$reason" --arg next "$next" \
        --argjson commands "$commands" --argjson provider "$provider_result" --argjson code "${1:-0}" \
        '{schemaVersion:1,tool:$tool,platform:$platform,status:$status,path:$path,version:$version,minimumVersion:$minimum,owner:$owner,reason:$reason,nextStep:$next,commands:$commands,providerResult:$provider,serviceOperations:false,exitCode:$code}'
}

discover
if [ "$status" = missing ] || [ "$status" = upgrade-needed ]; then provider; fi
if [ "$action" != ensure ]; then emit 0; exit 0; fi
case "$status" in
    reused) emit 0; exit 0 ;;
    conflict) emit 17; exit 17 ;;
    unavailable) emit 18; exit 18 ;;
esac
actual="$(detect_platform)"
if [ "$platform" != "$actual" ] && ! { [ "$platform" = linux ] && { [ "$actual" = ubuntu ] || [ "$actual" = debian ]; }; }; then
    status=unavailable; reason='plan platform differs from the actual target'; next='execute with the selected target Transport'; emit 18; exit 18
fi

code=0
case "$platform:$tool" in
    ubuntu:zsetup|debian:zsetup|linux:zsetup|istoreos:zsetup|openwrt:zsetup) bash "$here/bootstrap-core.sh" >&2 || code=$? ;;
    ubuntu:ks-cli|debian:ks-cli|linux:ks-cli)
        zsetup="${KAI_ZSETUP_BIN:-$(command -v zsetup 2>/dev/null || true)}"
        if [ -z "$zsetup" ] && [ -x "$HOME/.local/bin/zsetup" ]; then zsetup="$HOME/.local/bin/zsetup"; fi
        if [ -z "$zsetup" ]; then
            bash "$here/bootstrap-core.sh" >&2 || code=$?
            zsetup="$HOME/.local/bin/zsetup"
        fi
        if [ "$code" = 0 ]; then "$zsetup" install ks-cli --foreground >&2 || code=$?; fi ;;
    ubuntu:mise|debian:mise|linux:mise) bash "$here/install-mise.sh" >&2 || code=$? ;;
    windows:mise)
        provider_output="$(bash "$here/install-mise.sh")" || code=$?
        [ -z "$provider_output" ] || printf '%s\n' "$provider_output" >&2
        provider_result="$(printf '%s' "$provider_output" | jq -ce '{status,downloader,download,archiveCacheUsed,nativeExitCode}')" || provider_result=null ;;
    macos:mise) brew install mise >&2 || code=$? ;;
    istoreos:*|openwrt:*)
        baseline="$(mktemp /tmp/kai-system-curl.XXXXXX)"
        trap 'rm -f "$baseline"' EXIT
        sha256sum /usr/bin/curl /usr/lib/libcurl.so.* /usr/lib/libzstd.so.* /etc/opkg.conf > "$baseline"
        if [ "$tool" = bash ]; then opkg install bash >&2 || code=$?;
        else is-opkg install "$tool" >&2 || code=$?; fi
        sha256sum -c "$baseline" >&2 || code=11
        curl --version >&2 || code=11 ;;
    ubuntu:bash|debian:bash) apt-get install -y bash >&2 || code=$? ;;
    macos:bash) brew install bash >&2 || code=$? ;;
esac
if [ "$code" != 0 ]; then status=failed; reason='provider failed; preserve its original exit code and existing tool'; emit "$code"; exit "$code"; fi
# Recheck the executable, not the installer's success message.
discover
if [ -z "$path" ] || ! version_at_least "$version" "$minimum"; then status=failed; reason='installed executable is missing or incompatible'; emit 19; exit 19; fi
mkdir -p "$HOME/.local/share/kai/tools"
hash_file "$path" > "$HOME/.local/share/kai/tools/$tool.sha256"
status=installed; reason=; next=; emit 0
