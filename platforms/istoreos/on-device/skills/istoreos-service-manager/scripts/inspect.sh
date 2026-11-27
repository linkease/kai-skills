#!/bin/sh
# Observe files and native procd records. Never source/execute the inspected init script.
set -u
umask 077
kai_here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
kai_lib="$kai_here/../resources/runtime/kai-system-information/scripts/lib"
# Canonical common pack and installed full system collections have different roots.
[ -f "$kai_lib/receipt.sh" ] || kai_lib="$kai_here/../../../../common/skills/kai-system-information/scripts/lib"
[ -f "$kai_lib/receipt.sh" ] || kai_lib="$kai_here/../../../../../system-packs/common/skills/kai-system-information/scripts/lib"
. "$kai_lib/receipt.sh"
. "$kai_lib/probe.sh"
kai_operation=service.inspect kai_target= kai_service= kai_sections=init,config,runtime,logs
kai_deadline=5 kai_facts= kai_evidence= kai_errors= kai_evidence_index=0 kai_status=succeeded
kai_root=${ISTOREOS_ROOT:-} kai_file= kai_offset=0 kai_length=2048 kai_tmp=
kai_reader= kai_timer=
kai_log_count=null kai_log_pattern= kai_log_pattern_set=false kai_log_selection=false
kai_observed=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
kai_cleanup() {
  if [ -n "$kai_reader" ]; then kill -KILL "$kai_reader" 2>/dev/null || :; wait "$kai_reader" 2>/dev/null || :; fi
  if [ -n "$kai_timer" ]; then kill "$kai_timer" 2>/dev/null || :; wait "$kai_timer" 2>/dev/null || :; fi
  [ -z "$kai_tmp" ] || rm -rf -- "$kai_tmp"
}
trap kai_cleanup 0
trap 'exit 130' INT
trap 'exit 143' TERM HUP
kai_invalid() { kai_target=${kai_target:-unbound}; kai_status=failed; kai_error INVALID_ARGUMENT "$1"; kai_emit_observation; exit 2; }
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || kai_invalid 'An option value is missing.'
  case "$1" in
    --target-id) kai_target=$2 ;; --service) kai_service=$2 ;; --sections) kai_sections=$2 ;;
    --file) kai_file=$2 ;; --offset) kai_offset=$2 ;; --length) kai_length=$2 ;;
    --deadline-seconds) kai_deadline=$2 ;;
    --log-count)
      case "$2" in [1-9]|[1-9][0-9]|[1-9][0-9][0-9]|1000) kai_log_count=$2 ;; *) kai_invalid 'Log message count must be between 1 and 1000.' ;; esac
      kai_log_selection=true ;;
    --log-pattern)
      [ "${#2}" -le 256 ] || kai_invalid 'Log pattern exceeds its bound.'
      kai_log_pattern=$2 kai_log_pattern_set=true kai_log_selection=true ;;
    *) kai_invalid 'Unsupported option.' ;;
  esac
  shift 2
done
[ -n "$kai_target" ] && [ "${#kai_target}" -le 200 ] || kai_invalid 'A bound target ID is required.'
kai_require_bound_target || exit 2
case "$kai_service" in ''|*[!A-Za-z0-9._+-]*|*..*|-*) kai_invalid 'An explicit service identifier is required.' ;; esac
case "$kai_deadline:$kai_offset:$kai_length" in *[!0-9:]*) kai_invalid 'Bounds must be integers.' ;; esac
[ -n "$kai_offset" ] && [ "${#kai_offset}" -le 8 ] && [ -n "$kai_length" ] && [ "${#kai_length}" -le 4 ] && [ -n "$kai_deadline" ] && [ "${#kai_deadline}" -le 2 ] || kai_invalid 'Invalid bounds.'
[ "$kai_deadline" -ge 1 ] && [ "$kai_deadline" -le 30 ] && [ "$kai_length" -ge 1 ] && [ "$kai_length" -le 4096 ] || kai_invalid 'Invalid bounds.'
case "$kai_file" in ''|/*) : ;; *) kai_invalid 'File selection requires an absolute target path.' ;; esac
case "$kai_file" in */../*|*/..|*/./*) kai_invalid 'Path traversal is unsupported.' ;; esac
kai_old_ifs=$IFS; IFS=,
for kai_section in $kai_sections; do case "$kai_section" in init|config|runtime|logs|ownership) : ;; *) IFS=$kai_old_ifs; kai_invalid 'Unsupported section; choose init,config,runtime,logs,ownership. File windows use --file PATH.' ;; esac; done
IFS=$kai_old_ifs
[ -n "$kai_sections" ] || kai_invalid 'At least one section is required.'
if [ "$kai_log_selection" = true ]; then
  [ -z "$kai_file" ] && [ -z "$kai_root" ] || kai_invalid 'Log selectors apply only to the native logread stream.'
  case ",$kai_sections," in *,logs,*) : ;; *) kai_invalid 'Log selectors require the logs section.' ;; esac
fi
kai_tmp=$(mktemp -d "${TMPDIR:-/tmp}/kai-service-inspect.XXXXXX") || exit 2
kai_started=$(date +%s)
kai_has_section() { case ",$kai_sections," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
kai_jq_capable() {
  [ -n "$1" ] && [ -x "$1" ] || return 1
  [ "$("$1" -ne '(({a:[1]}|walk(.)|.a[0])==1) and (("中文"|tojson|fromjson)=="中文") and ("token"|test("token"))' 2>/dev/null)" = true ]
}
kai_select_jq() {
  if [ -n "${KAI_JQ_BIN:-}" ]; then
    case "$KAI_JQ_BIN" in /*) ;; *) return 1 ;; esac
    kai_jq_capable "$KAI_JQ_BIN" || return 1
    kai_json_tool=$KAI_JQ_BIN
    return 0
  fi
  kai_path_jq=$(command -v jq 2>/dev/null || :)
  for kai_candidate in "$kai_path_jq" "${HOME:-/nonexistent}/.local/bin/jq"; do
    if kai_jq_capable "$kai_candidate"; then kai_json_tool=$kai_candidate; return 0; fi
  done
  return 1
}
kai_redact() {
  kai_redact_input=$(cat)
  kai_redact_mode=$(printf '%s' "$kai_redact_input" | LC_ALL=C awk '
    { text=text (NR>1 ? "\n" : "") $0 }
    END {
      sub(/^[[:space:]]*/, "", text)
      first=substr(text,1,1)
      if ((first=="{" || first=="[") &&
          (tolower(text) ~ /(password|passwd|token|secret|api.?key|authorization|private.?key|[?&](key|auth)=)/ || index(text,"\\"))) print "json"
    }')
  if [ "$kai_redact_mode" = json ]; then
    kai_select_jq || return 1
    kai_redact_json=$(printf '%s' "$kai_redact_input" | "$kai_json_tool" -cs -f "$kai_here/redact-json.jq" 2>/dev/null) || return 1
    if [ -n "$kai_redact_json" ]; then printf '%s' "$kai_redact_json"
    else printf '%s' "$kai_redact_input"; fi
    return 0
  fi
  printf '%s' "$kai_redact_input" |
  sed -E \
    -e 's#(://)[^/@[:space:]]+:[^/@[:space:]]+@#\1[REDACTED]@#g' \
    -e 's#([?&](token|password|secret|key|auth)=)[^&[:space:]]+#\1[REDACTED]#gI' \
    -e 's#((password|passwd|token|secret|api_key|apikey|authorization|private_key)["\x27]?[[:space:]]*[:=][[:space:]]*).*#\1[REDACTED]#gI' \
    -e 's#(option[[:space:]]+(password|passwd|token|secret|key|username)[[:space:]]+).*#\1[REDACTED]#gI'
}

kai_text_file() {
  command -v awk >/dev/null 2>&1 || return 2
  # Reject binary/NUL and incomplete UTF-8 windows before shell variables can
  # discard bytes. No decoder, project code or downloaded dependency is run.
  LC_ALL=C awk '
    BEGIN {for(i=0;i<256;i++) byte[sprintf("%c",i)]=i; need=0; bad=0}
    {for(i=1;i<=length($0);i++) {
      n=byte[substr($0,i,1)]
      if(need) {if(n<minimum || n>maximum) bad=1; need--; minimum=128; maximum=191}
      else if(n==0) bad=1
      else if(n<128) {}
      else if(n>=194 && n<=223) {need=1;minimum=128;maximum=191}
      else if(n>=224 && n<=239) {need=2;minimum=(n==224?160:128);maximum=(n==237?159:191)}
      else if(n>=240 && n<=244) {need=3;minimum=(n==240?144:128);maximum=(n==244?143:191)}
      else bad=1
    }; if(need) bad=1}
    END {exit (bad || need)}' "$1"
}
# A file reader is one leaf process: it never executes descendants or source text.
# Minimal firmware may have neither timeout nor Perl. Bound this owned reader
# with a POSIX timer; arbitrary CLIs still require the shared bounded executor.
kai_read_window() {
  kai_probe_rc=0 kai_probe_output= kai_probe_error=
  kai_remaining=$((kai_deadline-$(date +%s)+kai_started))
  if [ "$kai_remaining" -le 0 ]; then kai_probe_rc=124; return; fi
  [ "$kai_remaining" -le 2 ] || kai_remaining=2
  rm -f "$kai_tmp/read-timeout"
  (ulimit -f 16 || exit 125; exec dd "if=$kai_root$kai_path" bs=1 "skip=$kai_offset" "count=$((kai_length+1))") >"$kai_tmp/out" 2>"$kai_tmp/err" &
  kai_reader=$!
  (
    kai_sleeper=
    trap '[ -z "$kai_sleeper" ] || { kill "$kai_sleeper" 2>/dev/null; wait "$kai_sleeper" 2>/dev/null; }; exit 0' TERM INT HUP
    sleep "$kai_remaining" & kai_sleeper=$!; wait "$kai_sleeper"; kai_sleeper=
    : >"$kai_tmp/read-timeout"
    kill -TERM "$kai_reader" 2>/dev/null
    sleep 1 & kai_sleeper=$!; wait "$kai_sleeper"; kai_sleeper=
    kill -KILL "$kai_reader" 2>/dev/null
  ) >/dev/null 2>&1 &
  kai_timer=$!
  wait "$kai_reader" 2>/dev/null || kai_probe_rc=$?
  kai_reader=
  kill "$kai_timer" 2>/dev/null || :
  wait "$kai_timer" 2>/dev/null || :
  kai_timer=
  if [ -f "$kai_tmp/read-timeout" ]; then kai_probe_rc=124; return; fi
  # Decode only after validating the complete byte sequence.
  kai_probe_output=
  kai_probe_error=$(head -c 4096 "$kai_tmp/err")
}
kai_read_file() {
  kai_name=$1 kai_path=$2
  if [ ! -e "$kai_root$kai_path" ]; then kai_fact "$kai_name" null "$kai_path" absent; return; fi
  if [ ! -f "$kai_root$kai_path" ] || [ ! -r "$kai_root$kai_path" ] || { [ -n "$kai_root" ] && [ -L "$kai_root$kai_path" ]; }; then kai_fact "$kai_name" null "$kai_path" denied; kai_error FILE_UNREADABLE 'The selected file is not a readable regular file within the selected root.'; return; fi
  kai_read_window
  if [ "$kai_probe_rc" -ne 0 ]; then kai_probe_unknown "$kai_name" "$kai_path" FILE_READ_FAILED; return; fi
  kai_bytes=$(wc -c < "$kai_root$kai_path" | tr -d ' ')
  if [ "$kai_bytes" -gt "$((kai_offset+kai_length))" ] && [ -z "$kai_file" ]; then
    kai_fact "$kai_name" "{\"path\":$(kai_json_string "$kai_path"),\"offset\":$kai_offset,\"limit\":$kai_length,\"hasMore\":true,\"content\":null}" "$kai_path" observed
    kai_error FILE_WINDOW_LIMIT 'The selected file exceeds this window; its text was not silently truncated. Explicit file/offset/length queries are available.'
    return
  fi
  kai_more=false
  if [ "$kai_bytes" -gt "$((kai_offset+kai_length))" ]; then
    kai_more=true
    head -c "$kai_length" "$kai_tmp/out" >"$kai_tmp/window"
    mv "$kai_tmp/window" "$kai_tmp/out"
  fi
  if ! kai_text_file "$kai_tmp/out"; then kai_fact "$kai_name" null "$kai_path" unknown; kai_error TEXT_ENCODING_UNAVAILABLE 'The selected window is not NUL-free UTF-8 text or its native validator is unavailable; no altered text was accepted.'; return; fi
  kai_probe_output=$(cat "$kai_tmp/out")
  if ! kai_text=$(printf '%s' "$kai_probe_output" | kai_redact); then
    kai_fact "$kai_name" null "$kai_path" unknown
    kai_error REDACTION_UNAVAILABLE 'Structured source could not be safely redacted using an existing jq; no source content was returned and nothing was installed.'
    return
  fi
  kai_redaction_field=
  [ "$kai_text" = "$kai_probe_output" ] || kai_redaction_field=',"redacted":true'
  kai_fact "$kai_name" "{\"path\":$(kai_json_string "$kai_path"),\"offset\":$kai_offset,\"limit\":$kai_length,\"hasMore\":$kai_more,\"untrusted\":true$kai_redaction_field,\"content\":$(kai_json_string "$kai_text")}" "$kai_path" observed
}
kai_command_fact() {
  kai_name=$1 kai_source=$2; shift 2
  kai_probe "$@"
  if [ "$kai_probe_rc" -eq 0 ]; then
    if ! kai_text_file "$kai_tmp/out"; then kai_fact "$kai_name" null "$kai_source" unknown; kai_error TEXT_ENCODING_UNAVAILABLE 'The native observation is not supported text; no altered text was accepted.'; return; fi
    if ! kai_text=$(printf '%s' "$kai_probe_output" | kai_redact); then
      kai_fact "$kai_name" null "$kai_source" unknown
      kai_error REDACTION_UNAVAILABLE 'Structured source could not be safely redacted using an existing jq; no source content was returned and nothing was installed.'
      return
    fi
    kai_redaction_field=
    [ "$kai_text" = "$kai_probe_output" ] || kai_redaction_field=',"redacted":true'
    kai_fact "$kai_name" "{\"untrusted\":true$kai_redaction_field,\"output\":$(kai_json_string "$kai_text"),\"exitCode\":0}" "$kai_source" observed
  else kai_probe_unknown "$kai_name" "$kai_source" NATIVE_QUERY_FAILED; fi
}
kai_fact service "$(kai_json_string "$kai_service")" 'explicit query parameter; not a health verdict' observed
if [ -n "$kai_file" ]; then
  kai_read_file selectedFile "$kai_file"
else
  if kai_has_section init; then
    kai_read_file initScript "/etc/init.d/$kai_service"
    kai_read_file firmwareInitScript "/rom/etc/init.d/$kai_service"
  fi
  if kai_has_section config; then
    kai_read_file configuration "/etc/config/$kai_service"
    if [ "$kai_service" = dockerd ]; then
      kai_read_file generatedConfiguration /tmp/dockerd/daemon.json
      kai_read_file storageRegistration /etc/quickstart/storage/docker.json
    fi
  fi
  if kai_has_section runtime; then
    # Fixture roots are file-only: do not accidentally query the controller procd.
    if [ -n "$kai_root" ]; then kai_read_file nativeServiceRecord "/run/kai-service/$kai_service.json"
    else kai_command_fact nativeServiceRecord 'ubus service list; a running process is not an API health check' ubus call service list "{\"name\":$(kai_json_string "$kai_service")}"
    fi
  fi
  if kai_has_section logs; then
    if [ -n "$kai_root" ]; then kai_read_file logs "/var/log/$kai_service.log"
    elif [ "$kai_log_selection" = true ]; then
      set -- logread
      [ "$kai_log_count" = null ] || set -- "$@" -l "$kai_log_count"
      kai_pattern_json=null
      if [ "$kai_log_pattern_set" = true ]; then
        set -- "$@" -e "$kai_log_pattern"
        kai_pattern_json=$(kai_json_string "$kai_log_pattern")
      fi
      kai_fact logSelection "{\"tailMessages\":$kai_log_count,\"pattern\":$kai_pattern_json,\"completeHistory\":false}" 'explicit native logread selection; not full history' observed
      kai_command_fact logs 'logread with explicit selection; original time and byte bounds retained' "$@"
    else kai_command_fact logs 'logread, unfiltered; oversized logs reported explicitly' logread; fi
  fi
  if kai_has_section ownership; then
    if [ -n "$kai_root" ]; then kai_fact packageOwnership null 'fixture roots do not use controller package commands' unsupported
    elif command -v opkg >/dev/null 2>&1; then kai_command_fact packageOwnership 'opkg search exact init script path' opkg search "/etc/init.d/$kai_service"
    elif command -v apk >/dev/null 2>&1; then kai_command_fact packageOwnership 'apk info --who-owns exact init script path' apk info --who-owns "/etc/init.d/$kai_service"
    else kai_fact packageOwnership null 'native package ownership command unavailable' unsupported; kai_error OWNERSHIP_UNAVAILABLE 'No supported existing package query command was found.'; fi
  fi
fi
kai_emit_observation
