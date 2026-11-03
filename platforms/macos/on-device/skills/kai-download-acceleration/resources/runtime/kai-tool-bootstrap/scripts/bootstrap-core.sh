#!/usr/bin/env bash
# First-time core only. Product installs use the core's existing downloader.
set -eu
umask 077
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
. "$here/jq-env.sh"
kai_use_jq basic || exit $?
lock="${KAI_BOOTSTRAP_RELEASE_LOCK:-$here/../references/tools.lock.json}"
case "$(uname -s)" in Linux) ;; *) echo 'no verified native core bootstrap registered' >&2; exit 18 ;; esac
case "$(uname -m)" in x86_64|amd64) arch=x86_64 ;; aarch64|arm64) arch=aarch64 ;; armv7l|armv7) arch=armv7 ;; *) echo 'unregistered core architecture' >&2; exit 18 ;; esac
version="$(jq -er '.zsetup.version' "$lock")"
url="$(jq -er --arg arch "$arch" '.zsetup.artifacts[$arch].url' "$lock")"
digest="$(jq -er --arg arch "$arch" '.zsetup.artifacts[$arch].sha256' "$lock")"
size="$(jq -er --arg arch "$arch" '.zsetup.artifacts[$arch].size' "$lock")"
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
printf '%s  %s\n' "$digest" "$stage/zsetup" | sha256sum -c - >&2 || exit 11
chmod 755 "$stage/zsetup"
[ "$("$stage/zsetup" --version)" = "zsetup $version" ] || exit 11
target="$HOME/.local/lib/linkease/zsetup/$version"
mkdir -p "$target"
if [ -e "$target/zsetup" ]; then
    printf '%s  %s\n' "$digest" "$target/zsetup" | sha256sum -c - >&2 || exit 11
else
    mv "$stage/zsetup" "$target/zsetup"
fi
ln -s "$target/zsetup" "$destination"
mkdir -p "$HOME/.local/share/kai/tools"
sha256sum "$destination" > "$HOME/.local/share/kai/tools/zsetup.sha256"
