macOS: reuse the original Homebrew installation when present. The ordinary Linux
ks-cli installer does not declare a macOS business mapping. Missing native
internal artifacts remain unavailable; do not manufacture a download URL.

Linux rescue core: the jq owner's bootstrap may retain its core under
`ZSETUP_ROOT/rescue/VERSION/zsetup` instead of registering a command. `probe
zsetup` recognizes the exact frozen Linux artifact after SHA256 and version
checks and reports `owner=zsetup-bootstrap-cache`. Pass the returned path as
`KAI_ZSETUP_BIN` on each dependent call. Discovery never executes or overwrites
a changed cache.

Windows: Git Bash/MSYS supplies Bash for common task scripts. PowerShell remains
the native first-time entry when Bash is absent. A System32/bash.exe or wsl.exe
launcher enters a separate Linux target and is not a Git Bash installation.
Run `powershell.exe -NoProfile -File scripts/bootstrap-bash.ps1 -Action Plan`
from a native shell, then use `-Action Ensure` for the requested installation.
The script uses the Git.Git entry from the winget source and its package checks;
if winget is unavailable it reports a concrete next step. It never downloads a
Linux Bash binary or treats the WSL launcher as Git Bash.
An existing trusted native tool may still be reused when its installer is
unavailable. Windows x64 mise has a source-locked ZIP provider through native
zsetup verification, independent of WinGet. An existing ks-cli obtains the ZIP
with automatic direct/gateway selection, without starting a Windows KSpeeder
service. Both mise.exe and mise-shim.exe are retained;
the returned path is used per task without a persistent PATH change. Native
macOS arm64 and Windows x64 test scope is recorded in the desktop verification
reports; those results do not extend to other architectures or unpublished clients.

iStoreOS: `is-opkg info ks-cli` exposes the standalone native client package;
install that package directly. Installing its reverse dependency istoreenhance
or luci-app-istoreenhance is a different service/application operation. The
native mise package owns mise-exec, `/lib/functions/mise.sh`, UCI runtime_dir and
runtime environment setup; use that integration on every independent call.

# Windows jq download routing

When Windows can reach an already authorized KSpeeder gateway but direct jq
download fails, resolve the original locked release URL with that gateway's
`POST /api/domainfold/remap`. Set `JQ_DOWNLOAD_BASE` to the HTTPS parent of the
returned jq artifact URL for this process, then repeat `ensure jq`. The existing
zsetup owner still validates its original size, SHA256 and functionality. Do not
disable those checks, start an unapproved service or set a system proxy. For
the current x64 lock the original artifact is
`https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-windows-amd64.exe`;
other architectures must use their own locked artifact rather than this URL.
