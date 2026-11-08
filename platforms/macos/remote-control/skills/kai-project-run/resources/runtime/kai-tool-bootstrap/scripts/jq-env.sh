# Source from Bash helpers. Selection changes only this process and its children.
kai_jq_capable() {
    [ -n "$1" ] && [ -x "$1" ] || return 1
    if [ "${2:-full}" = basic ]; then
        "$1" -ne '({a:1}|.a)==1' >/dev/null 2>&1
    else
        "$1" -ne '("abc"|test("^a")) and (("abc"|match("^a").string)=="a") and (("abc"|sub("^a";"x"))=="xbc") and (({text:"中文"}|tojson|fromjson|.text)=="中文")' >/dev/null 2>&1
    fi
}

kai_use_jq() {
    local required="${1:-full}" candidate existing
    if [ -n "${KAI_JQ_BIN:-}" ]; then
        candidate="$KAI_JQ_BIN"
        if command -v cygpath >/dev/null 2>&1; then candidate="$(cygpath -u "$candidate")"; fi
        kai_jq_capable "$candidate" "$required" || { echo 'selected KAI_JQ_BIN lacks required JSON/regex/Unicode support; preserve it' >&2; return 4; }
    else
        candidate=; existing="$(type -P jq 2>/dev/null || true)"
        for candidate in "$existing" "$HOME/.local/bin/jq" "$HOME/.local/bin/jq.exe"; do
            if kai_jq_capable "$candidate" full; then break; fi
            candidate=
        done
        if [ -z "$candidate" ] && [ "$required" = basic ] && kai_jq_capable "$existing" basic; then candidate="$existing"; fi
        [ -n "$candidate" ] || { echo 'complete jq is required; run the target kai-tool-bootstrap tool.sh ensure jq' >&2; return 4; }
    fi
    KAI_JQ_BIN="$candidate"; export KAI_JQ_BIN
    # Native Windows jq defaults to CRLF; binary mode keeps shell values intact.
    case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) KAI_JQ_NATIVE_WINDOWS=1 ;; *) KAI_JQ_NATIVE_WINDOWS=0 ;; esac
    jq() {
        if [ "$KAI_JQ_NATIVE_WINDOWS" = 1 ]; then command "$KAI_JQ_BIN" --binary "$@";
        else command "$KAI_JQ_BIN" "$@"; fi
    }
}
