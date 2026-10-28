#!/bin/sh
set -eu

usage() {
  echo "usage: target-ssh.sh inspect|plan|apply|verify|facts" >&2
  exit 2
}

phase="${1:-}"
case "$phase" in
  inspect|plan|verify|facts) ;;
  apply)
    [ "${TARGET_CHANGE_APPROVED:-}" = "YES" ] || {
      echo "failed: apply requires TARGET_CHANGE_APPROVED=YES after user approval" >&2
      exit 3
    }
    ;;
  *) usage ;;
esac
[ "$#" -eq 1 ] || usage

target_id="${TARGET_ID:-}"
host="${TARGET_SSH_HOST:-}"
user="${TARGET_SSH_USER:-}"
port="${TARGET_SSH_PORT:-22}"
known_hosts="${TARGET_SSH_KNOWN_HOSTS:-}"
identity="${TARGET_SSH_IDENTITY:-}"
timeout_seconds="${TARGET_TIMEOUT_SECONDS:-30}"
ssh_bin="${TARGET_SSH_BIN:-ssh}"
ssh_keygen_bin="${TARGET_SSH_KEYGEN_BIN:-ssh-keygen}"

case "$target_id" in ''|*[!A-Za-z0-9._:-]*) echo "failed: invalid or missing TARGET_ID" >&2; exit 2 ;; esac
case "$host" in ''|-*|*[!A-Za-z0-9._:-]*) echo "failed: invalid or missing TARGET_SSH_HOST" >&2; exit 2 ;; esac
case "$user" in ''|*[!A-Za-z0-9._-]*) echo "failed: invalid or missing TARGET_SSH_USER" >&2; exit 2 ;; esac
case "$port" in ''|*[!0-9]*) echo "failed: invalid TARGET_SSH_PORT" >&2; exit 2 ;; esac
case "$timeout_seconds" in ''|*[!0-9]*) echo "failed: invalid TARGET_TIMEOUT_SECONDS" >&2; exit 2 ;; esac
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { echo "failed: port out of range" >&2; exit 2; }
[ "$timeout_seconds" -ge 1 ] && [ "$timeout_seconds" -le 3600 ] || { echo "failed: timeout out of range" >&2; exit 2; }
[ -f "$known_hosts" ] || { echo "failed: TARGET_SSH_KNOWN_HOSTS must be an existing file" >&2; exit 2; }
[ -z "$identity" ] || [ -f "$identity" ] || { echo "failed: TARGET_SSH_IDENTITY is not a file" >&2; exit 2; }

lookup="$host"
[ "$port" = "22" ] || lookup="[$host]:$port"
"$ssh_keygen_bin" -F "$lookup" -f "$known_hosts" >/dev/null 2>&1 || {
  echo "failed: target host key is not pinned for $lookup" >&2
  exit 4
}

set -- \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=yes \
  -o "UserKnownHostsFile=$known_hosts" \
  -o "ConnectTimeout=$timeout_seconds" \
  -p "$port"
[ -z "$identity" ] || set -- "$@" -i "$identity"
set -- "$@" "$user@$host" sh -s

if [ "$phase" = "facts" ]; then
  exec_input='set -eu
printf "os_release="
(sed -n "s/^ID=//p" /etc/os-release 2>/dev/null || true) | head -n 1
printf "kernel="; uname -s 2>/dev/null || true
command -v sh >/dev/null 2>&1 && printf "feature=target-shell:posix\n"'
else
  exec_input="$(cat)"
fi

echo "target=$target_id transport=ssh phase=$phase" >&2
if command -v timeout >/dev/null 2>&1; then
  printf '%s\n' "$exec_input" | timeout "$timeout_seconds" "$ssh_bin" "$@"
else
  printf '%s\n' "$exec_input" | "$ssh_bin" "$@"
fi
