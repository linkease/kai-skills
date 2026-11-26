#!/bin/sh

validate_target() {
  domain="${1:-}"
  label="${2:-}"
  case "$domain" in
    system) ;;
    gui/*)
      uid="${domain#gui/}"
      case "$uid" in ''|*[!0-9]*) echo "failed: invalid gui uid" >&2; exit 2 ;; esac
      ;;
    *) echo "failed: domain must be system or gui/<uid>" >&2; exit 2 ;;
  esac
  case "$label" in
    ''|*[!A-Za-z0-9._-]*) echo "failed: invalid launchd label" >&2; exit 2 ;;
  esac
  service_target="$domain/$label"
}

# Uses the caller's bounded probe context. A registered job is not necessarily
# running; only the native state field or confirmed absence establishes state.
launchd_observe_state() {
  kai_state=unknown
  kai_probe launchctl print "$service_target"
  if [ "$kai_probe_rc" = 0 ]; then
    kai_native_state=$(printf '%s\n' "$kai_probe_output" | awk '/^[ \t]*state = / {sub(/^[ \t]*state = /, ""); print; exit}')
    case "$kai_native_state" in
      running) kai_state=running ;;
      'not running'|waiting|exited|'spawn scheduled') kai_state=stopped ;;
      *) return 1 ;;
    esac
  elif printf '%s' "$kai_probe_error" | grep -Eiq 'could not find service'; then kai_state=stopped
  else return 1; fi
}
