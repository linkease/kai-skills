---
name: kai-software
description: 按目标系统搜索、查询和安装软件，保留原包管理器与来源。
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources required by its own workflow.

## Local supporting resources

- `kai-tool-bootstrap`: [local instructions](resources/runtime/kai-tool-bootstrap/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

Prepare tools locally with `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`
and its explicit `ensure TOOL` operation when needed. Before Bash exists on Windows,
use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`
through native PowerShell, then the authorized Ensure operation.

## Business workflow
Use the local bootstrap resource above for missing Bash/tools.

Use the target's System Pack and Transport. Python/Node/Go SDK selection belongs
to kai-dev-environment; npm/pip/uv/Go project dependencies belong to
kai-project-dependencies. Do not install a system Python to satisfy a mise task.

`bash scripts/software.sh search TERM` returns bounded source-qualified IDs.
Use the selected `apt:NAME`, `opkg:NAME`, `istore:NAME`, `zsetup:NAME`,
`brew:FORMULA` or `winget:PACKAGE.ID` with
`info`, `install`, `files` and `remove`. A source is part of identity; never merge
two same-named candidates into one installation ID. Queries use cached indexes;
`refresh apt|opkg|istore|zsetup|brew|winget` is an explicit write. Desktop queries
retain their native provider's catalog policy; no implicit refresh command is issued.

On Windows, enter through Git Bash. The helper prefers an existing PowerShell 7
and otherwise uses Windows PowerShell. It uses the trusted
`Microsoft.WinGet.Client` module for structured results from the
selected `winget` source. Missing PowerShell or module is explicit, with no
automatic module installation. Exact IDs/source/version are checked before an
install and the registered version is checked afterward. Native failure status,
installer error and HRESULT remain in the failed receipt. File inventory/ownership
is explicitly unavailable from this provider. Use a trusted existing
`KAI_POWERSHELL_BIN` when discovery needs an explicit native path.

WinGet search/info use the native registered source directly. ks-cli does not
provide WinGet CONNECT routing. Prepared download/install may read the installed
Store-signed source index, acquire its version metadata and manifest through
`ks-cli download --mode=auto`, verify both source SHA256 values, and seed only
the command's isolated WinGet cache before native selection.
`install winget:PACKAGE.ID VERSION` uses the existing `ks-cli winget install`
adapter, retaining exact native selection and checking the registered version
afterward. Set `KAI_KSCLI_BIN` when that client is outside PATH, and
`KAI_WINGET_ARCH=x64|arm64|x86` for an explicit target architecture; otherwise
the native target architecture is used. Queries and removal retain the native
module API and do not start a service.

To acquire a package without installing it, use
`bash scripts/software.sh download winget:PACKAGE.ID VERSION 'D:/Downloads/package' x64`.
The explicit absolute directory and architecture are passed to the same prepared
client. `bash scripts/software.sh refresh winget` uses the client's original,
Store-signed source-package update and preserves its deployment receipt. These
operations require an existing compatible client; missing or invalid receipts
and nonzero native exits are failures. No automatic module or service install
is performed. Keep source, payload and CRL/OCSP health as separate results.

Do not set a WinGet proxy through this skill or describe a same-egress relay as
acceleration. Preserve native catalog failures; an explicit source refresh is
separate from a package query or installation.
See [WinGet acceleration](resources/winget-acceleration.md).

Check client provenance and native acceptance in that reference before using a
candidate. Missing or unverifiable metadata stops preparation. Ordinary direct
transfer is valid content; only an accelerated selected route proves acceleration.
Cached selection and payload transfer do not prove fresh catalog or CRL/OCSP health.

Search defaults to the native system provider. For internal software, use
`KAI_SOFTWARE_PROVIDER=zsetup`; for the iStore package catalog, use `istore`.
When a request spans sources, query each applicable cached provider and compare
their source-qualified results. A missing cache or an empty system repository
does not establish that the software is unavailable from other sources.
The zsetup index describes installers, not product releases: an unknown available
product version is `null` until its owner resolves release metadata. Installed
versions come from the installer's owned version layout without executing apps.

Inspect the version, manager, entrypoint and source before the requested
installation. `install ID VERSION` checks that exact version and verifies the
installed result. Afterward execute a meaningful command. Package status alone
does not prove the user's task works. Uninstall with the original manager and
preserve project files and modified configuration.

For `zsetup:linkspace`, `zsetup:ks-cli` and `zsetup:kspeeder`, removal calls the
zsetup-scripts owned resource in `resources/`, checked against `owner.lock.json`.
It verifies all owned program bytes, markers and links under the installer lock,
then removes program versions and command links. Config, data and download caches
remain. Modified or unknown version contents and foreign links cause a conflict
before deletion. This is a bundled local candidate, not a published zsetup verb;
do not invent `zsetup uninstall` or apply client removal to a managed service.

The iStore package provider is separate from ordinary OpenWrt feeds. Use the
native standalone ks-cli package for the client; its reverse dependencies
istoreenhance/LuCI belong to service/application workflows.

For an iStoreOS package failure, load the native manual istoreos-app-diagnostics helper. Its native-pack entry is istoreos-app-diagnostics/scripts/inspect.sh; resolve that helper through the target System Pack rather than a controller path.
