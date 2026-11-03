---
name: kai-tool-bootstrap
description: 准备 Bash、完整 jq、mise 和内部客户端，缺少校验过的原生发布物时明确报告。
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources required by its own workflow.
Prepare compatible Bash; the native Windows first entry is in this skill’s scripts/bootstrap-bash.ps1.

Start with `bash scripts/tool.sh plan jq`, then `ensure jq` when installation is
needed. This entry works without jq. Reuse a jq that actually supports JSON,
test/match/sub and Unicode; a version string alone is insufficient. A firmware
jq without regex support remains in place. The zsetup-scripts owner installs
the pinned complete jq in the user's managed directory; helpers select it per
process. No system jq/curl/library or global PATH change is required. An explicit
KAI_JQ_BIN is preserved and checked rather than silently replaced.

The embedded owner installer and source lock are a local candidate, executed
through existing zsetup run. They are not a claim that public `zsetup install jq`
is already activated. Once published, that index entry is the normal installer.
The owner's core bootstrap does not depend on jq, breaking the missing-jq cycle.
Desktop core availability and native validation remain separate gates.
On native Windows with neither jq nor a core, `ensure jq` calls the original
PowerShell core bootstrap, verifies the published Windows metadata and executable,
then runs the same jq owner. Its rescue cache uses `ZSETUP_ROOT`; it does not
register a service or substitute a Linux executable. Keep the returned core path
for later calls; a successful bootstrap is separate from complete desktop SDK tests.
`probe zsetup` also recognizes the verified Linux rescue cache. Use its returned
path as `KAI_ZSETUP_BIN` in each dependent call; changed caches are conflicts.
See [platform notes](data/platforms.md) for cache location and ownership.

Run `bash scripts/tool.sh probe TOOL` or `plan TOOL` first. `ensure TOOL` changes
the target and uses the reported provider. Reuse a compatible installation and
its manager. An external path with unknown ownership is a conflict; retain it.
`KAI_TRUSTED_TOOL_PATH` names an existing executable the caller has explicitly
chosen to trust. This is not permission to replace an old external installation.
The mise identity query runs offline only for `--version`; installation keeps
the caller's network and integrity policy. Homebrew ownership is checked from
its existing prefix, opt link and native installation receipt, without an online
formula lookup just to identify an installed program.

For Windows jq through an existing authorized gateway, see
[platform notes](data/platforms.md#windows-jq-download-routing). The original
owner's size, SHA256 and functionality checks remain required.

Ordinary Linux uses `zsetup install ks-cli --foreground`. The client package
does not install or start KSpeeder. iStoreOS uses `is-opkg install ks-cli` and its
native mise package, including mise-exec and UCI integration. Reuse firmware
curl/libcurl and preserve opkg configuration; bootstrap does not upgrade them.

If zsetup is missing, `ensure zsetup` independently bootstraps the pinned Linux
core on Ubuntu/Debian/iStoreOS/OpenWrt, including when full jq was already
reused and no rescue cache exists. This does not alter native mise/ks-cli ownership.

For first-time Linux zsetup only, the helper verifies a pinned official core
artifact before activation. Subsequent product downloads use zsetup's own
verification and transactions. Specify a persistent `KAI_TOOL_WORK_DIR` for
staging; do not infer persistence from available bytes alone.

On Windows x64, `plan mise` and `ensure mise` use the frozen official ZIP,
independently of WinGet. An existing `ks-cli` downloads it with `--mode=auto`,
allowing the client's speed policy to select direct access or its gateway.
Select a trusted native client with `KAI_KSCLI_BIN` when it is outside PATH.
Native zsetup >=0.4.0 still verifies the archive before installation. The installer retains both
`mise.exe` and `mise-shim.exe` in `$HOME/.local/bin`, with an ownership receipt;
use the returned executable path for subsequent calls. It does not edit PATH or
the user's mise configuration. Existing foreign or changed files are conflicts.
The public receipt includes the downloader and actual mode/strategy/selection;
a direct result is valid content but does not prove acceleration. No local
KSpeeder service is started: reuse an existing authorized gateway. Without a
client, the native zsetup path remains available and must be reported separately.
`KAI_DOWNLOAD_MODE` may explicitly choose auto/direct/accelerated/race; auto is
the default. Do not force an accelerated route merely to report acceleration.

An explicit `KAI_MISE_ARCHIVE_CACHE` may name an original ZIP staged through the
trusted Transport for offline use; its locked SHA256 and size remain required.
Do not substitute that cache test for a ks-cli online download test. If the
native core is missing, the original verified Windows core bootstrap prepares it first.

Missing macOS/Windows internal artifacts return `unavailable` with a next step;
never substitute a Linux binary. On Windows without Bash, use the native
PowerShell entry described in [platform notes](data/platforms.md).

Platform overrides are for an explicitly selected target or offline contracts;
they do not prove a connection or native acceptance. Each subsequent mise task
must establish its environment again rather than inherit a previous shell.

For Windows certificate-chain or revocation failures, use the independent native
PKI Plan/Repair/Restore entry in [Windows PKI notes](resources/windows-pki.md).
Validate current signed auxiliary material against existing target roots before
adding it to the current-user CA cache. Keep its ownership state for restoration
and expiration refresh; this is separate from command-scoped proxy selection.
