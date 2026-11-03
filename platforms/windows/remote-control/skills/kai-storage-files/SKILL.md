---
name: kai-storage-files
description: 限定路径分析空间与大文件、搜索文件名，核实安装目录的挂载和持久性。
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources required by its own workflow.

## Local supporting resources

- `kai-dev-environment`: [local instructions](resources/runtime/kai-dev-environment/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-tool-bootstrap`: [local instructions](resources/runtime/kai-tool-bootstrap/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

Prepare tools locally with `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`
and its explicit `ensure TOOL` operation when needed. Before Bash exists on Windows,
use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`
through native PowerShell, then the authorized Ensure operation.

SDK helpers are local at `resources/runtime/kai-dev-environment/scripts/runtime.sh`.

## Business workflow
Use the local bootstrap resource above for missing Bash/tools.

Use the selected target and Transport. `bash scripts/usage.sh space ROOT
[LIMIT [SECONDS]]` ranks live allocated file usage with Linkspace.
`search ROOT TERM [LIMIT [SECONDS]]` searches a literal filename term.
ROOT must be an existing absolute subdirectory. Defaults are 20 results and
30 seconds, with at most 1,000 results and 300 seconds. Bound the Transport
deadline as well; filesystem I/O can block inside native tools.

Linux x86_64/arm64/armv7 uses the published Linkspace program. Prepare it with
kai-software's `zsetup:linkspace` entry and its canonical owner installer, then
reuse the actual entrypoint. iStore/OpenWrt permits this portable user launcher
on the declared Linux architectures; native package integration still owns
mise and ks-cli. `KAI_LINKSPACE_BIN` selects an existing client explicitly.
Do not substitute a development build and label it published validation.

Linkspace always uses live scan, an explicit temporary directory outside ROOT,
a timeout and result limit; space analysis also has a 64 MiB scratch budget.
`KAI_USAGE_TEMP_DIR` selects an existing writable temporary directory. These
queries create no persistent index or source files. A Linkspace search item's
`path` is relative to its reported `root`, even when it starts with `/`; space
entries also expose actual `storagePath`. Preserve these native meanings.

macOS, Windows and architectures without a published Linkspace mapping use an
existing Python 3 standard-library adapter. Supply its verified path as
`KAI_USAGE_PYTHON`, for example from an already installed mise SDK. A read-only
query never installs that prerequisite. The report names `python-stdlib`, its
actual executable and observed kernel; it is not Linkspace validation. This
fallback bounds entries (default 10,000), depth, output and elapsed time, skips
symlinks/reparse points and child mounts, and reports logical sizes where native
allocation facts are absent. `KAI_USAGE_BACKEND=native` explicitly selects it.

`storage ROOT [MIN_FREE_BYTES]` only reads mount, capacity and permission facts.
Linux uses `zsetup storage`; macOS uses mount/statvfs; Windows uses Unicode
Win32 volume APIs. Available bytes alone never establish persistence. Overlay/
aufs, memory filesystems and unknown backing are ineligible for installation.
A successful observation can report `eligibleForInstall=false`. Mount-time
availability and future free space still require checking at installation time.

`cli probe|install|exec uv EXACT_VERSION [-- ARGUMENTS]` delegates to the mise
development CLI entrypoint in kai-dev-environment. Probe does not install;
installation leaves global selection unchanged. Verify the version/help and a
real subcommand, then report the selected executable and actual result. Project
dependencies still belong to kai-project-dependencies.

Keep native exits and stderr. Exit 11 means partial observations, with unreadable
ranges or a resource limit; report observed-only rankings and missing coverage.
It must not become a complete scan. Report the installation location, actual
command, result and next action. Cleanup, persistent indexing and broadening the
scope are separate tasks; do not delete files based only on size.
