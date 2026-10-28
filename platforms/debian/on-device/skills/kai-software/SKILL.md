---
name: kai-software
description: 按目标系统搜索、查询和安装软件，保留原包管理器与来源。
owner: system-pack/common
systems: ubuntu, debian, istoreos, openwrt, linux, macos, windows
triggers: 找软件, 文件管理插件, 找文件管理软件, 查询已安装软件, 升级系统软件包, 安装软件, 软件包, 应用商店, opkg, apk, 找软件安装到硬盘
negative-triggers: 安装 Python, 安装 Node, 安装 Go, pip install, npm ci, go mod
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
aliases: istoreos-package-manager
---

Before calling Bash scripts, prepare an existing compatible Bash with kai-tool-bootstrap. On Windows the first Bash bootstrap uses native PowerShell. Follow the selected target Transport; the controller OS does not choose the target package manager.

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

On Windows, enter through Git Bash. The helper uses an existing native PowerShell
and the trusted `Microsoft.WinGet.Client` module for structured results from the
selected `winget` source. Missing PowerShell or module is explicit, with no
automatic module installation. Exact IDs/source/version are checked before an
install and the registered version is checked afterward. Native failure status,
installer error and HRESULT remain in the failed receipt. File inventory/ownership
is explicitly unavailable from this provider. Use a trusted existing
`KAI_POWERSHELL_BIN` when discovery needs an explicit native path.

For a WinGet CDN connection reset, set `KAI_WINGET_ACCELERATION=required` with
`KAI_KSCLI_BIN`, an explicit trusted `KSPEEDER_WINGET_PROXY` CONNECT endpoint,
and `KAI_WINGET_SDK_DIR`. This candidate supports accelerated `search`/`info`;
other operations return unsupported rather than silently running direct.
The existing module branch remains available with acceleration `none`.
Prepare the pinned SDK with kai-tool-bootstrap's `prepare-winget-sdk.ps1`.
The worker needs native PowerShell 7.5+ (`KAI_WINGET_PWSH_BIN` when required)
and the current X64 lock; other SDK architectures are explicit unsupported gates.
It uses the official in-process SDK and the original registered official source,
verifies actual catalog/version provenance, and changes only its worker's WinINet
session. It does not enable the native CLI proxy policy or alter system proxies.
See [WinGet acceleration](resources/winget-acceleration.md).

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
