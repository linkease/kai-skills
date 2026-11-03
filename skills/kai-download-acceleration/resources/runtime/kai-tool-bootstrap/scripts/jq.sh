#!/usr/bin/env bash
# This entry must remain usable before jq exists.
set -eu
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
. "$here/jq-env.sh"
action="${1:-}"
case "$action" in probe|plan|ensure) ;; *) echo 'jq.sh probe|plan|ensure' >&2; exit 2 ;; esac
path=; version=; status=missing; code=0
escape_json() {
    local value="$1"
    value="${value//\\/\\\\}"; value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"; value="${value//$'\r'/\\r}"; value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}
emit() {
    printf '{"schemaVersion":1,"tool":"jq","status":"%s","path":"%s","version":"%s","serviceOperations":false,"sourceState":"local-candidate","exitCode":%s}\n' \
        "$status" "$(escape_json "$path")" "$(escape_json "$version")" "$code"
}
if kai_use_jq full 2>/dev/null; then
    path="$KAI_JQ_BIN";version="$(jq --version)";status=reused
    emit; exit 0
fi
if [ -n "${KAI_JQ_BIN:-}" ]; then status=conflict;code=4;emit;exit "$code";fi
if [ "$action" = plan ]; then status=install-needed;emit;exit 0;fi
if [ "$action" = probe ]; then code=4;emit;exit "$code";fi
case "$(uname -s):${KAI_PLATFORM:-}" in
    Linux:|Linux:linux|Linux:ubuntu|Linux:debian|Linux:istoreos|Linux:openwrt|Darwin:|Darwin:macos|MINGW*:|MINGW*:windows|MSYS*:|MSYS*:windows|CYGWIN*:|CYGWIN*:windows) ;;
    *) status=unavailable;code=18;emit;exit "$code" ;;
esac
resources="$here/../resources"
if command -v sha256sum >/dev/null 2>&1; then
    (cd "$resources" && sha256sum -c jq-owner.sha256) >&2
else
    (cd "$resources" && shasum -a 256 -c jq-owner.sha256) >&2
fi
core="${KAI_ZSETUP_BIN:-$(command -v zsetup 2>/dev/null || true)}"
[ -n "$core" ] || { [ ! -x "$HOME/.local/bin/zsetup" ] || core="$HOME/.local/bin/zsetup"; }
if [ -z "$core" ]; then
    case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*)
        # The canonical native owner can bootstrap its core without jq or Bash
        # downloads. Never send a Windows target into the POSIX Linux bootstrap.
        native_root="${ZSETUP_ROOT:-${TEMP:-/tmp}/zsetup}"
        core="$(env ZSETUP_ROOT="$(cygpath -w "$native_root")" powershell.exe -NoLogo -NoProfile -NonInteractive -File \
            "$(cygpath -w "$here/bootstrap-core-windows.ps1")")" || code=$?
        if [ "$code" != 0 ]; then status=failed;emit;exit "$code";fi
        core="$(cygpath -u "${core%$'\r'}")"
        [ -f "$core" ] && [ -x "$core" ] || { status=failed;code=11;emit;exit "$code"; }
        export KAI_ZSETUP_BIN="$core"
        ;; esac
fi
if [ -n "$core" ]; then
    # Original manager/ownership and core compatibility checks remain canonical.
    if kai_use_jq basic 2>/dev/null; then
        bash "$here/tool.sh" ensure zsetup >&2
    else
        # tool.sh itself needs basic jq. Validate an explicitly selected or
        # owner-verified core here without reintroducing the missing-jq cycle.
        core_version="$("$core" --version)"; core_version="${core_version%$'\r'}"
        [[ "$core_version" =~ ^zsetup\ ([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || { status=failed;code=4;emit;exit "$code"; }
        major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"; minimum_minor=5
        case "$(uname -s)" in Darwin|MINGW*|MSYS*|CYGWIN*) minimum_minor=4 ;; esac
        if [ "$major" -eq 0 ] && [ "$minor" -lt "$minimum_minor" ]; then status=failed;code=4;emit;exit "$code";fi
    fi
    arch="$("$core" context get arch)"
    arch="${arch%$'\r'}"
    env ZSETUP_BIN="$core" ZSETUP_INSTALLER_MODE=1 ZSETUP_ARCH="$arch" "$core" run -- sh "$resources/jq-install.sh" >&2 || code=$?
else
    # The owner's jq-independent core bootstrap breaks the missing-jq cycle.
    env ZSETUP_INSTALLER_MODE=0 sh "$resources/jq-install.sh" >&2 || code=$?
fi
if [ "$code" != 0 ]; then status=failed;emit;exit "$code";fi
kai_use_jq full || { status=failed;code=11;emit;exit "$code"; }
path="$KAI_JQ_BIN";version="$(jq --version)";status=installed;emit
