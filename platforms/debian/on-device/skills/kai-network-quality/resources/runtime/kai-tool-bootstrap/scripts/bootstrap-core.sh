#!/usr/bin/env bash
# First-time core only. Product installs use the core's existing downloader.
set -eu
umask 077
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
. "$here/jq-env.sh"
print_path=0
case "${1:-}" in "") ;; --print-path) print_path=1 ;; *) exit 2 ;; esac
case "$(uname -s)" in
    Linux)
        kai_use_jq basic || exit $?
        lock="${KAI_BOOTSTRAP_RELEASE_LOCK:-$here/../references/tools.lock.json}"
        case "$(uname -m)" in x86_64|amd64) arch=x86_64 ;; aarch64|arm64) arch=aarch64 ;; armv7l|armv7) arch=armv7 ;; *) echo 'unregistered core architecture' >&2; exit 18 ;; esac
        version="$(jq -er '.zsetup.version' "$lock")"
        url="$(jq -er --arg arch "$arch" '.zsetup.artifacts[$arch].url' "$lock")"
        digest="$(jq -er --arg arch "$arch" '.zsetup.artifacts[$arch].sha256' "$lock")"
        size="$(jq -er --arg arch "$arch" '.zsetup.artifacts[$arch].size' "$lock")"
        ;;
    Darwin)
        # First-time Mac jq preparation cannot parse a JSON lock yet. These
        # fixed fields select the existing verified immutable native release.
        case "$(uname -m)" in aarch64|arm64) ;; *) echo 'unregistered Mac core architecture' >&2;exit 18 ;; esac
        version=;url=;digest=;size=;arch=
        lock="${KAI_BOOTSTRAP_MACOS_LOCK:-$here/../references/zsetup-macos-aarch64.lock}"
        while IFS='=' read -r key value;do
            case "$key" in version) version=$value ;; url) url=$value ;; sha256) digest=$value ;; size) size=$value ;; arch) arch=$value ;; esac
        done < "$lock"
        [ "$version" = 0.4.0 ] && [ "$arch" = aarch64 ] || exit 11
        ;;
    *) echo 'no verified native core bootstrap registered' >&2;exit 18 ;;
esac
core_check_hash() {
    if command -v sha256sum >/dev/null 2>&1;then sha256sum -c -
    else shasum -a 256 -c -;fi
}
core_file_hash() {
    if command -v sha256sum >/dev/null 2>&1;then sha256sum "$1"
    else shasum -a 256 "$1";fi
}
case "$size" in ''|*[!0-9]*) exit 11 ;; esac
[ "$size" -gt 0 ] && [ "$size" -le 67108864 ] || exit 11
case "$url" in https://*) ;; *) echo 'HTTPS required' >&2; exit 14 ;; esac
[[ "$digest" =~ ^[a-fA-F0-9]{64}$ ]] || exit 11
case "$version" in ''|*[!a-zA-Z0-9._+-]*) exit 11 ;; esac
work="${KAI_TOOL_WORK_DIR:-$HOME/.local/share/kai/bootstrap}"
case "$work" in /*) ;; *) echo 'absolute persistent staging directory required' >&2; exit 12 ;; esac
mkdir -p "$work" "$HOME/.local/bin"
available="$(df -Pk "$work" | awk 'END {print $4}')"
[ "$available" -ge 65536 ] || { echo 'bootstrap needs at least 64MiB free' >&2; exit 12; }
destination="$HOME/.local/bin/zsetup"
[ ! -e "$destination" ] && [ ! -L "$destination" ] || { echo 'refusing to replace an existing core' >&2; exit 17; }
stage="$(mktemp -d "$work/core.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
trap 'exit 130' INT TERM HUP
curl --proto '=https' --proto-redir '=https' -fsSL --connect-timeout 10 --max-time 120 --max-filesize "$size" -o "$stage/zsetup" "$url"
[ "$(wc -c < "$stage/zsetup" | tr -d ' ')" = "$size" ] || exit 11
printf '%s  %s\n' "$digest" "$stage/zsetup" | core_check_hash >&2 || exit 11
chmod 755 "$stage/zsetup"
[ "$("$stage/zsetup" --version)" = "zsetup $version" ] || exit 11
target="$HOME/.local/lib/linkease/zsetup/$version"
mkdir -p "$target"
if [ -e "$target/zsetup" ]; then
    printf '%s  %s\n' "$digest" "$target/zsetup" | core_check_hash >&2 || exit 11
else
    mv "$stage/zsetup" "$target/zsetup"
fi
ln -s "$target/zsetup" "$destination"
mkdir -p "$HOME/.local/share/kai/tools"
core_file_hash "$destination" > "$HOME/.local/share/kai/tools/zsetup.sha256"

[ "$print_path" != 1 ] || printf '%s\n' "$destination"
