#!/bin/sh
set -eu
#!/bin/sh
set -eu

WORK_ROOT=${ZSETUP_ROOT:-/tmp/zsetup}
DEFAULT_PRIMARY_BASES="https://dl.istoreos.com/binary https://fw.d4ctech.com/binary https://fw20.koolcenter.com/binary"
DEFAULT_FALLBACK_BASE="https://fw.koolcenter.com/binary"
if [ -n "${ZSETUP_BOOTSTRAP_BASES:-}" ]; then
    BOOTSTRAP_BASES=$ZSETUP_BOOTSTRAP_BASES
    DIRECT_PRIMARY_BASES=$ZSETUP_BOOTSTRAP_BASES
    DIRECT_FALLBACK_BASE=
else
    BOOTSTRAP_BASES="$DEFAULT_PRIMARY_BASES $DEFAULT_FALLBACK_BASE"
    DIRECT_PRIMARY_BASES=$DEFAULT_PRIMARY_BASES
    DIRECT_FALLBACK_BASE=$DEFAULT_FALLBACK_BASE
fi
INSECURE_CONFIRMED=0

status() {
    printf '%s\n' "$*" >&2
}

bootstrap_mips_byte_order() {
    command -v od >/dev/null 2>&1 || return 1
    set -- $(od -An -tu1 -N6 /bin/sh 2>/dev/null)
    [ "$#" -eq 6 ] && [ "$1" = 127 ] && [ "$2" = 69 ] && [ "$3" = 76 ] && [ "$4" = 70 ] && [ "$6" = 1 ]
}

bootstrap_arch() {
    case "$(uname -m 2>/dev/null || true)" in
        x86_64|amd64) ZSETUP_ARCH=x86_64 ;;
        aarch64|arm64) ZSETUP_ARCH=aarch64 ;;
        armv7l|armv7) ZSETUP_ARCH=armv7 ;;
        mipsel|mipsle) ZSETUP_ARCH=mipsel ;;
        mips)
            # uname alone does not identify byte order. ELF EI_DATA=1 is little endian.
            bootstrap_mips_byte_order || { echo "zsetup: MIPS byte order is unsupported or unknown" >&2; return 2; }
            ZSETUP_ARCH=mipsel ;;
        *) echo "zsetup: unsupported architecture" >&2; return 2 ;;
    esac
    case "$(uname -s 2>/dev/null || true)" in
        Darwin)
            ZSETUP_ARTIFACT="zsetup-macos-$ZSETUP_ARCH"
            ZSETUP_STABLE_PATH=zsetup/stable-macos ;;
        Linux)
            ZSETUP_ARTIFACT="zsetup-linux-$ZSETUP_ARCH"
            ZSETUP_STABLE_PATH=zsetup/stable ;;
        *) echo "zsetup: unsupported operating system" >&2; return 2 ;;
    esac
}

bootstrap_url() {
    scheme=$1
    base=$2
    path=$3
    authority_path=${base#*://}
    printf '%s://%s/%s\n' "$scheme" "${authority_path%/}" "$path"
}

bootstrap_fetch_from_base() {
    scheme=$1
    base=$2
    remote_path=$3
    destination=$4
    found=0
    url=$(bootstrap_url "$scheme" "$base" "$remote_path")
    if command -v curl >/dev/null 2>&1; then
        found=1
        rm -f "$destination" 2>/dev/null || true
        if curl -fsSL --connect-timeout 10 --max-time 30 -o "$destination" "$url"; then
            return 0
        fi
    fi
    if command -v wget >/dev/null 2>&1; then
        found=1
        rm -f "$destination" 2>/dev/null || true
        if wget -q -T 10 -O "$destination" "$url"; then
            return 0
        fi
    fi
    [ "$found" -eq 1 ] || echo "zsetup: curl or wget is required for first bootstrap" >&2
    return 1
}

bootstrap_fetch() {
    scheme=$1
    remote_path=$2
    destination=$3
    for base in $BOOTSTRAP_BASES; do
        if bootstrap_fetch_from_base "$scheme" "$base" "$remote_path" "$destination"; then
            return 0
        fi
    done
    return 1
}

confirm_insecure_http() {
    [ "$INSECURE_CONFIRMED" -eq 0 ] || return 0
    echo "zsetup: all HTTPS bootstrap sources failed." >&2
    echo "WARNING: HTTP can be intercepted; both zsetup and checksum metadata may be replaced." >&2
    printf 'Continue with insecure HTTP bootstrap? [y/N] ' >&2
    confirm_file=${ZSETUP_CONFIRM_FILE:-/dev/tty}
    answer=
    if ! IFS= read -r answer < "$confirm_file"; then
        echo >&2
        echo "zsetup: HTTP bootstrap refused because no interactive confirmation is available" >&2
        return 1
    fi
    case "$answer" in
        y|Y|yes|YES) INSECURE_CONFIRMED=1; echo "zsetup: user accepted insecure HTTP bootstrap" >&2 ;;
        *) echo "zsetup: insecure HTTP bootstrap declined" >&2; return 1 ;;
    esac
}

read_stable_version() {
    file=$1
    IFS= read -r RESCUE_VERSION < "$file" || return 1
    case "$RESCUE_VERSION" in
        ''|*[!0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz._+-]*) return 1 ;;
    esac
    [ -n "$RESCUE_VERSION" ] && [ "${#RESCUE_VERSION}" -le 64 ] || return 1
    compatibility_version=${RESCUE_VERSION%%[-+]*}
    compatibility_major=${compatibility_version%%.*}
    compatibility_rest=${compatibility_version#*.}
    compatibility_minor=${compatibility_rest%%.*}
    compatibility_patch=${compatibility_rest#*.}
    case "$compatibility_major:$compatibility_minor:$compatibility_patch" in *[!0123456789:]*|::*|*::*) return 1 ;; esac
    if [ "$compatibility_major" -eq 0 ]; then
        [ "$compatibility_minor" -ge 5 ] || return 1
    fi
}

read_expected_sha256() {
    file=$1
    EXPECTED_SHA256=
    while IFS=' ' read -r digest name remainder; do
        name=${name#\*}
        if [ "$name" = "$ZSETUP_ARTIFACT" ] && [ -z "${remainder:-}" ]; then
            EXPECTED_SHA256=$digest
            break
        fi
    done < "$file"
    [ "${#EXPECTED_SHA256}" -eq 64 ] || return 1
    case "$EXPECTED_SHA256" in *[!0123456789abcdefABCDEF]*) return 1 ;; esac
}

have_hash_tool() {
    command -v sha256sum >/dev/null 2>&1 || command -v openssl >/dev/null 2>&1
}

hash_matches() {
    [ -f "$1" ] || return 1
    if [ -z "${EXPECTED_SHA256:-}" ]; then
        echo "zsetup: bootstrap SHA-256 verification skipped; HTTPS transport remains required" >&2
        return 0
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$1")
        actual=${actual%% *}
    elif command -v openssl >/dev/null 2>&1; then
        actual=$(openssl dgst -sha256 "$1")
        actual=${actual##*= }
    else
        echo "zsetup: bootstrap SHA-256 tool disappeared before verification" >&2
        return 1
    fi
    [ "$actual" = "$EXPECTED_SHA256" ]
}

is_expected_zsetup() {
    [ -x "$1" ] && [ "$("$1" --version 2>/dev/null || true)" = "zsetup $RESCUE_VERSION" ]
}

find_existing_zsetup() {
    if [ -n "${ZSETUP_BIN:-}" ] && is_expected_zsetup "$ZSETUP_BIN"; then
        ACTIVE_ZSETUP=$ZSETUP_BIN
        return 0
    fi
    if is_expected_zsetup "$WORK_ROOT/rescue/$RESCUE_VERSION/zsetup"; then
        ACTIVE_ZSETUP="$WORK_ROOT/rescue/$RESCUE_VERSION/zsetup"
        return 0
    fi
    if command -v zsetup >/dev/null 2>&1; then
        system_zsetup=$(command -v zsetup)
        if is_expected_zsetup "$system_zsetup"; then
            ACTIVE_ZSETUP=$system_zsetup
            return 0
        fi
    fi
    return 1
}

fetch_bootstrap_metadata() {
    scheme=$1
    stable_file=$2
    sums_file=$3
    for base in $BOOTSTRAP_BASES; do
        bootstrap_fetch_from_base "$scheme" "$base" "$ZSETUP_STABLE_PATH" "$stable_file" || continue
        read_stable_version "$stable_file" || continue
        EXPECTED_SHA256=
        if have_hash_tool && bootstrap_fetch_from_base "$scheme" "$base" "zsetup/$RESCUE_VERSION/SHA256SUMS" "$sums_file"; then
            read_expected_sha256 "$sums_file" || EXPECTED_SHA256=
        fi
        return 0
    done
    echo "zsetup: no source returned valid stable metadata over $scheme" >&2
    return 1
}

bootstrap_zsetup() {
    bootstrap_arch
    state_dir="$WORK_ROOT/bootstrap"
    mkdir -p "$state_dir"
    stable_file="$state_dir/.stable.$$"
    sums_file="$state_dir/.SHA256SUMS.$$"
    trap 'rm -f "$stable_file" "$sums_file" "${candidate:-}" 2>/dev/null || true' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    metadata_scheme=https
    if ! fetch_bootstrap_metadata https "$stable_file" "$sums_file"; then
        confirm_insecure_http
        metadata_scheme=http
        fetch_bootstrap_metadata http "$stable_file" "$sums_file"
    fi

    if find_existing_zsetup; then
        trap - EXIT HUP INT TERM
        rm -f "$stable_file" "$sums_file" 2>/dev/null || true
        return 0
    fi

    rescue_dir="$WORK_ROOT/rescue/$RESCUE_VERSION"
    rescue_bin="$rescue_dir/zsetup"
    candidate="$rescue_dir/.zsetup-download.$$"
    mkdir -p "$rescue_dir"
    if ! bootstrap_fetch https "zsetup/$RESCUE_VERSION/$ZSETUP_ARTIFACT" "$candidate"; then
        confirm_insecure_http
        bootstrap_fetch http "zsetup/$RESCUE_VERSION/$ZSETUP_ARTIFACT" "$candidate"
    fi
    hash_matches "$candidate" || {
        echo "zsetup: bootstrap checksum mismatch" >&2
        return 1
    }
    chmod 0755 "$candidate"
    is_expected_zsetup "$candidate" || {
        echo "zsetup: downloaded bootstrap has the wrong product or version" >&2
        return 1
    }
    mv -f "$candidate" "$rescue_bin"
    ACTIVE_ZSETUP=$rescue_bin
    trap - EXIT HUP INT TERM
    rm -f "$stable_file" "$sums_file" 2>/dev/null || true
    [ "$metadata_scheme" = https ] || echo "zsetup: insecure HTTP bootstrap completed with user consent" >&2
}

jq_release_artifact() {
    jq_version=1.8.2
    case "$1:$2" in
        linux:amd64) jq_artifact=jq-linux-amd64; jq_sha=b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f; jq_size=2267912; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-amd64 ;;
        linux:arm64) jq_artifact=jq-linux-arm64; jq_sha=8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309; jq_size=1797688; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-arm64 ;;
        linux:armel) jq_artifact=jq-linux-armel; jq_sha=d88f6bd640ef8909b3deb587f12c03a0ed38fe8bd5e2e882e2b1bf88f5dab8d2; jq_size=1700244; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-armel ;;
        linux:armhf) jq_artifact=jq-linux-armhf; jq_sha=78458244fb546469b4042e9e07cf78714ef6848895eb9515df76b4eb0b1dc992; jq_size=1340000; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-armhf ;;
        linux:i386) jq_artifact=jq-linux-i386; jq_sha=ba996e8ce436973e2f39e2639405a37e8c81ba8c722b71c83996278ad0af16dd; jq_size=2156424; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-i386 ;;
        linux:mips) jq_artifact=jq-linux-mips; jq_sha=1e9930ef7c4e69a49c2e5e9a1a5b1240a36d10123fa8524952ddeaedc039ad72; jq_size=2007040; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-mips ;;
        linux:mips64) jq_artifact=jq-linux-mips64; jq_sha=34e53f8df8298fd609f8e3dcc7eae1d8a741976f289909286601443caf64229a; jq_size=2081176; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-mips64 ;;
        linux:mips64el) jq_artifact=jq-linux-mips64el; jq_sha=eb382d2419aa99c82b8fb1cbb0d1cfa3da71b0852108f9140ca1ddcfd3d33d81; jq_size=2081176; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-mips64el ;;
        linux:mips64r6) jq_artifact=jq-linux-mips64r6; jq_sha=365c0bcda2e695ab1e6f3372094d812e914784c03aa45ca4b67b93cc54fc78d9; jq_size=2015472; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-mips64r6 ;;
        linux:mips64r6el) jq_artifact=jq-linux-mips64r6el; jq_sha=01bfe1a1579cfac74a680870031e1d4bdd500040fae18fd9e2a27ada8e555a80; jq_size=2015472; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-mips64r6el ;;
        linux:mipsel) jq_artifact=jq-linux-mipsel; jq_sha=9570c9dcbd7d0de85b16a00046a3e5a9ba72aabe4b85c8f5f8b5927aed8d664e; jq_size=2072576; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-mipsel ;;
        linux:mipsr6) jq_artifact=jq-linux-mipsr6; jq_sha=d2105ab249e66dc14465982d4b8b3e8cf0e6301eb606fa6116dfe0bfacbfb918; jq_size=1941296; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-mipsr6 ;;
        linux:mipsr6el) jq_artifact=jq-linux-mipsr6el; jq_sha=5e66dcad39eaa2d1e5b2eb01e2f378a3bfdf0ee2ebeb571cc87512ca4f38dec6; jq_size=1941296; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-mipsr6el ;;
        linux:powerpc) jq_artifact=jq-linux-powerpc; jq_sha=d60c33574fdeab53ae15feb37598249ce4ab6a344adde6f22abba38cf7a8de6e; jq_size=2187392; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-powerpc ;;
        linux:ppc64el) jq_artifact=jq-linux-ppc64el; jq_sha=0dba61281e525ced2111bc00c8bd8078100e8822c33bfb35feee95314bbeeea2; jq_size=2453424; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-ppc64el ;;
        linux:riscv64) jq_artifact=jq-linux-riscv64; jq_sha=a96e5a78a7b2c5a0575bc2a10dda4b20d84efd8c02c8806539ee5f5e57603e8d; jq_size=1609208; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-riscv64 ;;
        linux:s390x) jq_artifact=jq-linux-s390x; jq_sha=42b3306c786e3352e3097b8aa03ca0e5631bdc7a6bf133bb8ddd9e4b148d20c8; jq_size=1990096; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-s390x ;;
        macos:amd64) jq_artifact=jq-macos-amd64; jq_sha=e94b266e3c26690550006abe63152b782280f4e14374accdf04cbde844f00bc0; jq_size=871768; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-macos-amd64 ;;
        macos:arm64) jq_artifact=jq-macos-arm64; jq_sha=2d75340ba57a4b4b4c8708a21c2dc8e958a48aaa8bba13b27f77f6e4c0eca07e; jq_size=841504; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-macos-arm64 ;;
        windows:amd64) jq_artifact=jq-windows-amd64.exe; jq_sha=a6fc67fedaf9128a3309a1e2ebb8b986aeccf70122ee46d2cb4849e423f0c627; jq_size=1035264; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-windows-amd64.exe ;;
        windows:arm64) jq_artifact=jq-windows-arm64.exe; jq_sha=083b5377392bc57cf27052b6d20a2d927770683bca844632901ff38b4b7b0ac7; jq_size=973312; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-windows-arm64.exe ;;
        windows:i386) jq_artifact=jq-windows-i386.exe; jq_sha=a99cb668f95bdd788d9ee20529613b115e5d2a0d7f9127ee6976607e878558ba; jq_size=1082368; jq_url=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-windows-i386.exe ;;
        *) return 2 ;;
    esac
}

# jq release policy. Native zsetup owns HTTPS, SHA256, size and download caching.
jq_resolve() {
    jq_os=${ZSETUP_OS:-}
    if [ -z "$jq_os" ]; then
        case "$(uname -s)" in Linux) jq_os=linux ;; Darwin) jq_os=macos ;; MINGW*|MSYS*|CYGWIN*) jq_os=windows ;; *) return 2 ;; esac
    fi
    case "$jq_os" in linux|ubuntu|debian|istoreos|openwrt) jq_os=linux ;; darwin|macos) jq_os=macos ;; windows) ;; *) return 2 ;; esac
    jq_arch=${ZSETUP_ARCH:-$(uname -m)}
    case "$jq_arch" in x86_64|amd64) jq_arch=amd64 ;; aarch64|arm64) jq_arch=arm64 ;; armv7|armv7l) jq_arch=armhf ;; i386|i686|x86) jq_arch=i386 ;; esac
    jq_release_artifact "$jq_os" "$jq_arch" || { printf '%s\n' 'jq: no verified artifact for this platform/architecture' >&2; return 2; }
}

jq_install() {
    jq_resolve || return $?
    if [ "${1:-}" = --plan ] && [ "$#" = 1 ]; then
        printf 'application=jq\nversion=%s\nplatform=%s\nartifact=%s\nsha256=%s\nsize=%s\nurl=%s\n' \
            "$jq_version" "$jq_os" "$jq_artifact" "$jq_sha" "$jq_size" "$jq_url"
        return
    fi
    jq_prefix=${ZSETUP_INSTALL_PREFIX:-$HOME/.local/lib/linkease/jq}; jq_action=install
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --installer-prefix) [ "$#" -ge 2 ] || return 2; jq_prefix=$2; shift 2 ;;
            --remove) jq_action=remove; shift ;;
            *) printf '%s\n' 'jq: unsupported installer argument' >&2; return 2 ;;
        esac
    done
    : "${ZSETUP_BIN:?an existing zsetup is required}"
    if [ "$jq_os" = windows ] && command -v cygpath >/dev/null 2>&1; then
        ZSETUP_BIN=$(cygpath -u "$ZSETUP_BIN")
        jq_prefix=$(cygpath -u "$jq_prefix")
    fi
    jq_extension=; [ "$jq_os" != windows ] || jq_extension=.exe
    jq_command="$HOME/.local/bin/jq$jq_extension"
    jq_check_path "$jq_prefix" && jq_check_path "${jq_command%/*}" || return 2
    [ ! -L "$jq_prefix/.managed" ] || return 2
    if [ -e "$jq_prefix/.managed" ]; then
        [ "$(cat "$jq_prefix/.managed")" = jq ] || return 2
    else
        [ "$jq_action" != remove ] || return 0
        [ ! -e "$jq_command" ] && [ ! -L "$jq_command" ] || return 2
        for jq_entry in "$jq_prefix"/* "$jq_prefix"/.[!.]* "$jq_prefix"/..?*; do
            [ ! -e "$jq_entry" ] && [ ! -L "$jq_entry" ] || return 2
        done
        umask 077; mkdir -p "$jq_prefix"
        (set -C; printf 'jq\n' > "$jq_prefix/.managed") || return 2
    fi
    [ ! -L "$jq_prefix/current" ] || return 2
    jq_old=
    if [ -e "$jq_prefix/current" ]; then
        jq_old=$(cat "$jq_prefix/current")
        jq_valid_version "$jq_old" || return 2
    fi
    if [ -e "$jq_command" ] || [ -L "$jq_command" ]; then
        [ ! -L "$jq_command" ] && [ -f "$jq_command" ] && [ -n "$jq_old" ] || return 2
        jq_check_version_path "$jq_old" || return 2
        cmp -s "$jq_command" "$jq_prefix/versions/$jq_old/bin/jq$jq_extension" || {
            printf '%s\n' 'jq: preserve the conflicting command' >&2; return 11;
        }
    fi
    umask 077
    mkdir "$jq_prefix/.install-lock" || return 2
    jq_stage=; jq_committed=0; jq_replacing=0
    trap 'jq_cleanup' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    jq_stage=$(mktemp -d "$jq_prefix/.download.XXXXXX") || return 12
    if [ "$jq_action" = remove ]; then jq_remove; return $?; fi
    jq_check_version_path "$jq_version" || return 2
    jq_bin="$jq_prefix/versions/$jq_version/bin/jq$jq_extension"
    jq_output="$jq_stage/product"
    # Let native zsetup revalidate an owned existing file through its SHA cache.
    [ ! -f "$jq_bin" ] || jq_output=$jq_bin
    # Prepared bytes are a cache input, validated by native zsetup against the
    # original release SHA256/size. Never overwrite an owned version with an
    # unvalidated cache, and never follow an external cache symlink.
    if [ "$jq_output" != "$jq_bin" ] && [ -n "${JQ_ARTIFACT_CACHE:-}" ]; then
        [ -f "$JQ_ARTIFACT_CACHE" ] && [ ! -L "$JQ_ARTIFACT_CACHE" ] || return 2
        cp "$JQ_ARTIFACT_CACHE" "$jq_output" || return 12
    fi
    set -- "$ZSETUP_BIN" download -o "$jq_output" --sha256 "$jq_sha" --size "$jq_size"
    [ -z "${ZSETUP_CA_FILE:-}" ] || set -- "$@" --ca-file "$ZSETUP_CA_FILE"
    if [ -n "${JQ_DOWNLOAD_BASE:-}" ]; then
        case "$JQ_DOWNLOAD_BASE" in https://*) ;; *) return 2 ;; esac
        jq_url="${JQ_DOWNLOAD_BASE%/}/$jq_artifact"
    fi
    "$@" "$jq_url" || return $?
    chmod 0755 "$jq_output" || return 12
    [ "$("$jq_output" --version | tr -d '\r')" = "jq-$jq_version" ] || return 11
    "$jq_output" -ne '("abc"|test("^a")) and (("abc"|match("^a").string)=="a") and (("abc"|sub("^a";"x"))=="xbc") and (({text:"中文"}|tojson|fromjson|.text)=="中文")' || return 11
    mkdir -p "${jq_bin%/*}" "${jq_command%/*}" || return 12
    if [ "$jq_output" != "$jq_bin" ]; then mv "$jq_output" "$jq_bin" || return 12; fi
    printf '%s:%s\n' "$jq_sha" "$jq_size" > "$jq_bin.verified" || return 12
    [ ! -f "$jq_command" ] || cp "$jq_command" "$jq_stage/old-command" || return 12
    cp "$jq_bin" "${jq_command}.candidate.$$" || return 12
    chmod 0755 "${jq_command}.candidate.$$"
    jq_replacing=1
    mv -f "${jq_command}.candidate.$$" "$jq_command" || return 12
    printf '%s\n' "$jq_version" > "$jq_stage/current"
    mv -f "$jq_stage/current" "$jq_prefix/current" || return 12
    jq_committed=1
    printf 'application=jq\nversion=%s\ncommand=%s\nexecutable=%s\nfunctionalValidation=passed\n' "$jq_version" "$jq_command" "$jq_bin"
}

jq_file_sha() {
    if command -v sha256sum >/dev/null 2>&1; then jq_digest=$(sha256sum < "$1") || return 11
    elif command -v shasum >/dev/null 2>&1; then jq_digest=$(shasum -a 256 < "$1") || return 11
    else printf '%s\n' 'jq removal requires native SHA256 support' >&2; return 127; fi
    jq_digest=${jq_digest%% *}
}

jq_remove() {
    # Complete validation precedes every deletion; configuration and staging
    # outside the owned versions remain in place.
    [ ! -L "$jq_prefix/versions" ] || return 11
    for jq_dir in "$jq_prefix"/versions/* "$jq_prefix"/versions/.[!.]* "$jq_prefix"/versions/..?*; do
        [ -e "$jq_dir" ] || [ -L "$jq_dir" ] || continue
        jq_valid_version "${jq_dir##*/}" || return 11
        jq_check_version_path "${jq_dir##*/}" || return 11
        [ -d "$jq_dir/bin" ] || return 11
        jq_file="$jq_dir/bin/jq$jq_extension"
        [ -f "$jq_file" ] && [ -f "$jq_file.verified" ] || return 11
        jq_record=$(cat "$jq_file.verified")
        jq_record_sha=${jq_record%%:*};jq_record_size=${jq_record#*:}
        case "$jq_record_sha" in *[!a-f0-9]*|'') return 11 ;; esac
        [ "${#jq_record_sha}" = 64 ] || return 11
        jq_file_sha "$jq_file" || return $?
        [ "$jq_digest" = "$jq_record_sha" ] && [ "$(wc -c < "$jq_file" | tr -d ' ')" = "$jq_record_size" ] || return 11
        for jq_entry in "$jq_dir"/* "$jq_dir"/.[!.]* "$jq_dir"/..?*; do
            [ -e "$jq_entry" ] || [ -L "$jq_entry" ] || continue
            [ "$jq_entry" = "$jq_dir/bin" ] || return 11
        done
        for jq_entry in "$jq_dir/bin"/* "$jq_dir/bin"/.[!.]* "$jq_dir/bin"/..?*; do
            [ -e "$jq_entry" ] || [ -L "$jq_entry" ] || continue
            case "$jq_entry" in "$jq_file"|"$jq_file.verified") ;; *) return 11 ;; esac
        done
    done
    for jq_dir in "$jq_prefix"/versions/*; do
        [ -d "$jq_dir" ] || continue
        rm -f "$jq_dir/bin/jq$jq_extension" "$jq_dir/bin/jq$jq_extension.verified"
        rmdir "$jq_dir/bin" "$jq_dir" || return 12
    done
    [ ! -d "$jq_prefix/versions" ] || rmdir "$jq_prefix/versions" || return 12
    rm -f "$jq_command" "$jq_prefix/current" "$jq_prefix/.managed"
    jq_committed=1
    printf 'application=jq\nstatus=removed\n'
}

jq_valid_version() {
    case "$1" in ''|*[!0-9.]*|.*|*..*|*.) return 2 ;; esac
    jq_remaining=${1#*.}; [ "$jq_remaining" != "$1" ] || return 2
    jq_remaining=${jq_remaining#*.}; case "$jq_remaining" in ''|*.*) return 2 ;; esac
}

jq_check_path() {
    case "$1" in /*) ;; *) return 2 ;; esac
    case "$1" in /|/bin|/sbin|/usr|/usr/*|/etc|/etc/*|*/../*|*/..|*/./*|*/.|*//*|*'
'*|*'
'*) return 2 ;; esac
    jq_parent=$1
    while [ "$jq_parent" != / ]; do
        [ ! -L "$jq_parent" ] || return 2
        [ ! -e "$jq_parent" ] || [ -d "$jq_parent" ] || return 2
        jq_parent=${jq_parent%/*}; [ -n "$jq_parent" ] || jq_parent=/
    done
}

jq_check_version_path() {
    jq_valid_version "$1" || return 2
    jq_check_path "$jq_prefix/versions/$1/bin" || return 2
    jq_file="$jq_prefix/versions/$1/bin/jq$jq_extension"
    for jq_path in "$jq_file" "$jq_file.verified"; do
        [ ! -L "$jq_path" ] || return 2
        [ ! -e "$jq_path" ] || [ -f "$jq_path" ] || return 2
    done
}

jq_cleanup() {
    if [ "$jq_replacing" = 1 ] && [ "$jq_committed" = 0 ]; then
        if [ -f "$jq_stage/old-command" ]; then mv -f "$jq_stage/old-command" "$jq_command"; else rm -f "$jq_command"; fi
    fi
    rm -f "${jq_command}.candidate.$$"
    [ -z "$jq_stage" ] || rm -rf "$jq_stage"
    rmdir "$jq_prefix/.install-lock"
}

main() {
    case "${1:-}" in
        --plan) jq_install "$@" ;;
        --help) printf '%s\n' 'jq-install.sh [--plan|--remove] [--installer-prefix ABSOLUTE_DIRECTORY]' 'Installs only a pinned, verified jq; preserves the system executable.' ;;
        *)
            if [ "${ZSETUP_INSTALLER_MODE:-0}" != 1 ] && [ -z "${ZSETUP_BIN:-}" ]; then
                bootstrap_zsetup || return $?
                ZSETUP_BIN=$ACTIVE_ZSETUP
            fi
            jq_install "$@" ;;
    esac
}
main "$@"
