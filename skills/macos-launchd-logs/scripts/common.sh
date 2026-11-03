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
