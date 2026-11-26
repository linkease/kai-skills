#!/bin/sh
# Shared boundary check; this file does not enter or alter the integration.
runtime_environment_check() {
  integrated_home="$(uci -q get mise.main.runtime_dir)" || {
    echo 'failed: runtime directory is not configured' >&2; return 4;
  }
  case "$integrated_home" in /*) ;; *) echo 'failed: configured runtime directory must be absolute' >&2; return 4 ;; esac
  [ "${HOME:-}" = "$integrated_home" ] && [ -d "$integrated_home" ] && [ -w "$integrated_home" ] || {
    echo 'failed: incorrect integration HOME or unavailable runtime directory' >&2; return 4;
  }
  # mise exec deliberately replaces shims with selected SDK bin directories.
  # Only its checked child path may use this mode; callers verify SDK identity.
  if [ "${1:-entry}" = selected ]; then return 0; fi
  case ":${PATH:-}:" in *":$HOME/.local/share/mise/shims:"*) ;; *)
    echo 'failed: missing integrated shims; inspect mise-exec' >&2; return 4 ;;
  esac
}
