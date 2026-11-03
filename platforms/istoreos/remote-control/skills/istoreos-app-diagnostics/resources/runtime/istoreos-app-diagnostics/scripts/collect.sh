#!/bin/sh
set -eu

requested="${1:-latest}"
detail="${2:-}"
root="${ISTORE_DIAG_ROOT:-}"
now="${ISTORE_DIAG_NOW:-$(date +%s)}"
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"

case "$requested" in
  latest|[A-Za-z0-9][A-Za-z0-9._+-]*) ;;
  *) echo "usage: collect.sh <latest|app-id> [--detail]" >&2; exit 2 ;;
esac
case "$now" in ''|*[!0-9]*) now=0 ;; esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
status_file="${ISTORE_DIAG_TASK_STATUS_FILE:-$tmp/task-status.json}"
log_file="${ISTORE_DIAG_LOG_FILE:-${root}/var/log/tasks/istore.log}"

if [ -z "${ISTORE_DIAG_TASK_STATUS_FILE:-}" ]; then
  tasks_init="${root}/etc/init.d/tasks"
  if [ -x "$tasks_init" ]; then
    "$tasks_init" task_status istore >"$status_file" 2>/dev/null || :
  else
    : >"$status_file"
  fi
fi

json_field() {
  field="$1"
  if [ ! -s "$status_file" ]; then
    return 0
  elif command -v jsonfilter >/dev/null 2>&1; then
    jsonfilter -i "$status_file" -e "@.$field" 2>/dev/null || :
  elif command -v jq >/dev/null 2>&1; then
    jq -r --arg field "$field" 'if has($field) then .[$field] else empty end' "$status_file" 2>/dev/null || :
  else
    sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^,\"}]*\).*/\1/p" "$status_file" | head -n 1
  fi
}

running="$(json_field running)"
start="$(json_field start)"
stop="$(json_field stop)"
exit_code="$(json_field exit_code)"
command_text="$(json_field command)"

task_app="$(printf '%s\n' "$command_text" | sed -n 's/.*app-meta-\([A-Za-z0-9._+-]*\).*/\1/p' | head -n 1)"
action="$(printf '%s\n' "$command_text" | sed -n "s/.*['\" ]\(install\|upgrade\|remove\)['\" ].*/\1/p" | head -n 1)"
autoconf_requested=false
if printf '%s\n' "$command_text" | grep -F "AUTOCONF=$task_app" >/dev/null 2>&1; then autoconf_requested=true; fi
enable_requested="$(printf '%s\n' "$command_text" | sed -n 's/.*enable=\([01]\).*/\1/p' | head -n 1)"
target_path="$(printf '%s\n' "$command_text" | sed -n "s#.*path=['\"]*\(/[^ '\"]*\).*#\1#p" | head -n 1)"

if [ "$requested" = latest ]; then
  effective_app="$task_app"
else
  effective_app="$requested"
fi

if [ -z "$task_app" ]; then
  correlation=none
elif [ "$effective_app" = "$task_app" ]; then
  correlation=exact
else
  correlation=mismatch
fi

case "$running" in
  true|1) state=running ;;
  false|0) state=finished ;;
  *) state=unknown ;;
esac

age=
timestamp="$stop"
case "$timestamp" in ''|0|*[!0-9]*) timestamp="$start" ;; esac
case "$timestamp" in
  ''|*[!0-9]*) ;;
  *)
    if [ "$now" -ge "$timestamp" ]; then age=$((now - timestamp)); else age=0; fi
    ;;
esac

if [ "$detail" = --detail ]; then
  ISTORE_DIAG_LOG_MAX_BYTES="${ISTORE_DIAG_LOG_DETAIL_MAX_BYTES:-32768}"
else
  ISTORE_DIAG_LOG_MAX_BYTES="${ISTORE_DIAG_LOG_MAX_BYTES:-8192}"
fi
export ISTORE_DIAG_LOG_MAX_BYTES

log_available=false
log_truncated=false
if [ -s "$log_file" ]; then
  log_available=true
  raw_size="$(wc -c <"$log_file" | tr -d ' ')"
  if [ "$raw_size" -gt "$ISTORE_DIAG_LOG_MAX_BYTES" ]; then log_truncated=true; fi
fi

printf 'requested_app\t%s\n' "$effective_app"
printf 'task_app\t%s\n' "$task_app"
printf 'state\t%s\n' "$state"
printf 'correlation\t%s\n' "$correlation"
printf 'exit_code\t%s\n' "$exit_code"
printf 'action\t%s\n' "$action"
printf 'autoconf_requested\t%s\n' "$autoconf_requested"
printf 'enable_requested\t%s\n' "$enable_requested"
printf 'target_path\t%s\n' "$target_path"
printf 'start\t%s\n' "$start"
printf 'stop\t%s\n' "$stop"
printf 'age_seconds\t%s\n' "$age"
printf 'log_available\t%s\n' "$log_available"
printf 'log_truncated\t%s\n' "$log_truncated"
printf '%s\n' '--LOG--'
if [ "$log_available" = true ]; then
  "$script_dir/sanitize-log.sh" <"$log_file"
fi
