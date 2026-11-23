---
name: kai-dev-environment
description: 用 mise 安装、验证和执行 Python、Node、Go SDK 与开发 CLI。
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
在实际目标的 Transport 中执行；缺 Bash/mise 时用 kai-tool-bootstrap，Windows 首次用原生 PowerShell。系统包走 kai-software，项目依赖走 kai-project-dependencies。

`bash scripts/runtime.sh resolve RUNTIME SELECTOR` 查询 mise 目录，得到完整版本后再 `probe RUNTIME VERSION`。需要安装时用 `install RUNTIME VERSION [none|project|global]`，默认 none；项目/全局选择只在已有授权内修改，不把历史版本当 latest。

`verify RUNTIME VERSION` 验证来源和可运行性；`exec RUNTIME VERSION -- COMMAND...` 执行实际程序，每次重新进入选定 SDK。保留原生退出码；SDK 验证不代表项目成功。Python 使用预编译包，不隐式装编译器；TLS、签名及 Go 校验保持开启。

安装失败时用 `bash scripts/diagnose.sh LOG_FILE ORIGINAL_EXIT_CODE` 分类证据，不重试安装。iStore/OpenWrt 的真实 mise-exec、运行目录及 Python 进程级 crypto 适配由脚本处理；不修改系统 crypto/CA，不绕过用户 OPENSSL_CONF。[Python 适配](data/python-openssl.md) 仅在对应故障时阅读。

需要加速时先由 kai-download-acceleration 确认现有网关，再用 `KAI_RUNTIME_ACCELERATION=required`；不在 SDK 操作中启动服务，不静默直连重试。公共 Go Git 元数据另用 `KAI_GO_GIT_METADATA=required`，仅进程设置，不用于私有仓库。

开发 CLI 用 `bash scripts/dev-cli.sh probe|install|exec uv VERSION [-- ARG...]`；其他 profile 未支持。安装不改变全局选择，仍验证真实版本及子命令。
