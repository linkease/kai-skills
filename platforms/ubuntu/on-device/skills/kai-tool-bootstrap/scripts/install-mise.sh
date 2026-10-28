#!/usr/bin/env bash
# A pinned official release; download/capture verification is owned by zsetup.
set -eu
umask 077
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
. "$here/jq-env.sh"
kai_use_jq full || exit $?
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        core="${KAI_ZSETUP_BIN:-$(command -v zsetup 2>/dev/null || true)}"
        if [ -z "$core" ] && [ -x "$HOME/.local/bin/zsetup.exe" ]; then core="$HOME/.local/bin/zsetup.exe"; fi
        if [ -z "$core" ]; then
            (cd "$here/../resources" && sha256sum -c jq-owner.sha256) >&2
            native_root="${ZSETUP_ROOT:-${TEMP:-/tmp}/zsetup}"
            core="$(env ZSETUP_ROOT="$(cygpath -w "$native_root")" powershell.exe -NoLogo -NoProfile -NonInteractive \
                -File "$(cygpath -w "$here/bootstrap-core-windows.ps1")")"
            core="${core%$'\r'}"
        fi
        core="$(cygpath -w "$core")"
        lock="${KAI_BOOTSTRAP_RELEASE_LOCK:-$here/../references/tools.lock.json}"
        args=(-NoLogo -NoProfile -NonInteractive -File "$(cygpath -w "$here/install-mise-windows.ps1")"
            -Action Ensure -Destination "$(cygpath -w "$HOME/.local/bin/mise.exe")"
            -Core "$core" -ReleaseLock "$(cygpath -w "$lock")" -DownloadMode "${KAI_DOWNLOAD_MODE:-auto}")
        client="${KAI_KSCLI_BIN:-$(command -v ks-cli 2>/dev/null || true)}"
        if [ -n "$client" ]; then args+=(-KsCli "$(cygpath -w "$client")"); fi
        if [ -n "${KAI_MISE_ARCHIVE_CACHE:-}" ]; then args+=(-ArchiveCache "$(cygpath -w "$KAI_MISE_ARCHIVE_CACHE")"); fi
        exec powershell.exe "${args[@]}" ;;
    Linux) ;;
    *) echo 'use the native platform provider' >&2; exit 18 ;;
esac
case "$(uname -m)" in x86_64|amd64) arch=x64 ;; aarch64|arm64) arch=arm64 ;; *) exit 18 ;; esac
lock="${KAI_BOOTSTRAP_RELEASE_LOCK:-$here/../references/tools.lock.json}"
version="$(jq -er '.mise.version' "$lock")"
url="$(jq -er --arg arch "linux-$arch" '.mise.artifacts[$arch].url' "$lock")"
digest="$(jq -er --arg arch "linux-$arch" '.mise.artifacts[$arch].sha256' "$lock")"
size="$(jq -er --arg arch "linux-$arch" '.mise.artifacts[$arch].size' "$lock")"
case "$url" in https://*) ;; *) exit 14 ;; esac
download_urls=("$url")
jq -e --arg arch "linux-$arch" '(.mise.artifacts[$arch].mirrors // []) | type == "array" and length <= 2 and all(.[]; type == "string" and startswith("https://") and (test("[\r\n]") | not))' "$lock" >/dev/null || exit 14
while IFS= read -r mirror; do
    [ -z "$mirror" ] || download_urls+=("$mirror")
done < <(jq -r --arg arch "linux-$arch" '.mise.artifacts[$arch].mirrors // [] | .[]' "$lock")
[[ "$digest" =~ ^[a-fA-F0-9]{64}$ ]] || exit 11
case "$version" in ''|*[!a-zA-Z0-9._+-]*) exit 11 ;; esac
zsetup="${KAI_ZSETUP_BIN:-$(command -v zsetup 2>/dev/null || true)}"
if [ -z "$zsetup" ] && [ -x "$HOME/.local/bin/zsetup" ]; then zsetup="$HOME/.local/bin/zsetup"; fi
if [ -z "$zsetup" ]; then bash "$here/bootstrap-core.sh"; zsetup="$HOME/.local/bin/zsetup"; fi
destination="$HOME/.local/bin/mise"
[ ! -e "$destination" ] && [ ! -L "$destination" ] || { echo 'refusing to replace existing mise' >&2; exit 17; }
work="${KAI_TOOL_WORK_DIR:-$HOME/.local/share/kai/bootstrap}"
case "$work" in /*) ;; *) exit 12 ;; esac
mkdir -p "$work" "$HOME/.local/bin"
stage="$(mktemp -d "$work/mise.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
trap 'exit 130' INT TERM HUP
"$zsetup" download -o "$stage/mise.tar.gz" --sha256 "$digest" --size "$size" \
    --overall-timeout 360s --probe-timeout 90s --connect-timeout 15s --read-idle-timeout 90s \
    --max-bytes 67108864 --min-free-bytes 134217728 "${download_urls[@]}"
"$zsetup" capture -o "$stage/mise" --max-bytes 134217728 --min-free-bytes 67108864 \
    -- tar -xOzf "$stage/mise.tar.gz" mise/bin/mise
chmod 755 "$stage/mise"
case "$("$stage/mise" --version)" in "$version "*|"$version") ;; *) exit 11 ;; esac
target="$HOME/.local/lib/linkease/mise/$version/bin"
mkdir -p "$target"
if [ -e "$target/mise" ]; then cmp "$stage/mise" "$target/mise" || exit 11;
else mv "$stage/mise" "$target/mise"; fi
ln -s "$target/mise" "$destination"
mkdir -p "$HOME/.local/share/kai/tools"
sha256sum "$destination" > "$HOME/.local/share/kai/tools/mise.sha256"
