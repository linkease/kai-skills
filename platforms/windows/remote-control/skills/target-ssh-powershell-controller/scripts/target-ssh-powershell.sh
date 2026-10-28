#!/bin/sh
set -eu

phase="${1:-}"
case "$phase" in inspect|plan|verify|facts) ;; apply) [ "${TARGET_CHANGE_APPROVED:-}" = "YES" ] || { echo "failed: apply requires approval" >&2; exit 3; } ;; *) echo "usage: target-ssh-powershell.sh inspect|plan|apply|verify|facts" >&2; exit 2 ;; esac
[ "$#" -eq 1 ] || exit 2

target_id="${TARGET_ID:-}"
host="${TARGET_SSH_HOST:-}"
user="${TARGET_SSH_USER:-}"
port="${TARGET_SSH_PORT:-22}"
known_hosts="${TARGET_SSH_KNOWN_HOSTS:-}"
identity="${TARGET_SSH_IDENTITY:-}"
timeout_seconds="${TARGET_TIMEOUT_SECONDS:-30}"
ssh_bin="${TARGET_SSH_BIN:-ssh}"
keygen_bin="${TARGET_SSH_KEYGEN_BIN:-ssh-keygen}"

case "$target_id" in ''|*[!A-Za-z0-9._:-]*) echo "failed: invalid TARGET_ID" >&2; exit 2 ;; esac
case "$host" in ''|-*|*[!A-Za-z0-9._:-]*) echo "failed: invalid TARGET_SSH_HOST" >&2; exit 2 ;; esac
case "$user" in ''|*[!A-Za-z0-9._-]*) echo "failed: invalid TARGET_SSH_USER" >&2; exit 2 ;; esac
case "$port" in ''|*[!0-9]*) echo "failed: invalid port" >&2; exit 2 ;; esac
case "$timeout_seconds" in ''|*[!0-9]*) echo "failed: invalid timeout" >&2; exit 2 ;; esac
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || exit 2
[ "$timeout_seconds" -ge 1 ] && [ "$timeout_seconds" -le 3600 ] || exit 2
[ -f "$known_hosts" ] || { echo "failed: pinned known_hosts file is required" >&2; exit 2; }
[ -z "$identity" ] || [ -f "$identity" ] || exit 2
lookup="$host"; [ "$port" = 22 ] || lookup="[$host]:$port"
"$keygen_bin" -F "$lookup" -f "$known_hosts" >/dev/null 2>&1 || { echo "failed: target host key is not pinned" >&2; exit 4; }

set -- -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
  -o "UserKnownHostsFile=$known_hosts" -o "ConnectTimeout=$timeout_seconds" -p "$port"
[ -z "$identity" ] || set -- "$@" -i "$identity"
# An outer PowerShell SSH shell can normalize any child failure to 1. Return
# the child status on a separate, per-call stderr frame instead of trusting it.
for dependency in iconv base64 awk mktemp; do
  command -v "$dependency" >/dev/null 2>&1 || { echo "failed: missing $dependency" >&2; exit 18; }
done
scratch="$(mktemp -d "${TMPDIR:-/tmp}/kai-psssh.XXXXXXXX")"
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
marker="KAI_SSH_EXIT_$(basename "$scratch")_$$="
# Only this small launcher goes on the Windows command line. The UTF-8 payload
# stays on stdin, avoiding Windows command-line length limits and shell quoting.
launcher="$(cat <<'PS'
$ProgressPreference = 'SilentlyContinue'
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$file = [IO.Path]::Combine([IO.Path]::GetTempPath(), [Guid]::NewGuid().ToString('N') + '.ps1')
$code = 255
try {
  [IO.File]::WriteAllText($file, [Console]::In.ReadToEnd(), (New-Object System.Text.UTF8Encoding($true)))
  # Keep param/using/#requires in the original script at their original position.
  $child = '[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); $ProgressPreference = ''SilentlyContinue''; & ''' + $file.Replace("'","''") + '''; $ok=$?; if ($null -ne $LASTEXITCODE) {exit $LASTEXITCODE}; if (!$ok) {exit 1}'
  $childEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($child))
  $start = New-Object Diagnostics.ProcessStartInfo
  $start.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
  $start.Arguments = '-NoLogo -NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand ' + $childEncoded
  $start.UseShellExecute = $false
  $process = [Diagnostics.Process]::Start($start)
  $process.WaitForExit()
  $code = $process.ExitCode
  $process.Dispose()
} finally {
  if ([IO.File]::Exists($file)) { [IO.File]::Delete($file) }
}
PS
)"
launcher="$launcher
[Console]::Error.WriteLine([Environment]::NewLine + '$marker' + \$code)
exit \$code"
encoded="$(printf '%s' "$launcher" | iconv -f UTF-8 -t UTF-16LE | base64 | tr -d '\r\n')"
set -- "$@" "$user@$host" powershell.exe -NoLogo -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand "$encoded"

if [ "$phase" = facts ]; then
  script='$result = [ordered]@{platform=[Environment]::OSVersion.Platform.ToString(); version=[Environment]::OSVersion.Version.ToString(); architecture=$env:PROCESSOR_ARCHITECTURE; psVersion=$PSVersionTable.PSVersion.ToString()}; $result | ConvertTo-Json -Compress'
else
  script="$(cat)"
fi
# Keep the supervisor off the Windows command line too. The user payload stays
# a separate BOM file, preserving param/using/#requires at its original position.
payload="$(printf '%s\n' "$script" | base64 | tr -d '\r\n')"
supervisor="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)/supervise.ps1"
[ -f "$supervisor" ] || { echo 'failed: remote supervisor missing' >&2; exit 18; }
script="\$kaiPayload = '$payload'
\$kaiTimeout = $timeout_seconds
$(cat "$supervisor")"
echo "target=$target_id transport=ssh shell=powershell phase=$phase" >&2
ssh_status=0
if command -v timeout >/dev/null 2>&1; then
  printf '%s\n' "$script" | timeout "$((timeout_seconds + 15))" "$ssh_bin" "$@" 2>"$scratch/stderr" || ssh_status=$?
else
  printf '%s\n' "$script" | "$ssh_bin" "$@" 2>"$scratch/stderr" || ssh_status=$?
fi
# Preserve user stderr; remove only the exact frame generated by this call.
awk -v marker="$marker" -v status_file="$scratch/status" '
  { line=$0; sub(/\r$/, "", line)
    if (index(line, marker)==1 && substr(line,length(marker)+1) ~ /^-?[0-9]+$/) {
      code=substr(line,length(marker)+1); print ((code % 256)+256)%256 > status_file
    } else print $0 > "/dev/stderr"
  }' "$scratch/stderr"
case "$ssh_status" in 124|137|255) exit "$ssh_status" ;; esac
[ -s "$scratch/status" ] || { echo "failed: remote exit-status frame missing" >&2; exit 255; }
exit "$(cat "$scratch/status")"
