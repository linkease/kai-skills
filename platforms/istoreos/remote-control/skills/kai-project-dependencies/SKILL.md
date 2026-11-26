---
name: kai-project-dependencies
description: 在指定 SDK、管理器和项目中查询来源或执行依赖操作；保留锁格式和项目隔离。
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.

## Local supporting resources

- `kai-dev-environment`: [local instructions](resources/runtime/kai-dev-environment/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-tool-bootstrap`: [local instructions](resources/runtime/kai-tool-bootstrap/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

Optional tool preparation: `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`
or the separately authorized `ensure TOOL` operation. The native Windows preparation interface is
use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`
through existing native PowerShell. Querying this skill does not install missing tools.

SDK helpers are local at `resources/runtime/kai-dev-environment/scripts/runtime.sh`.

## Operation interfaces
`bash scripts/dependencies.sh sources MANAGER VERSION PROJECT` 查询来源；`install MANAGER VERSION PROJECT` 在现有项目中执行相应依赖事务；`run MANAGER VERSION PROJECT -- ARGS...` 执行显式原生参数。明确变更入口有 `add npm ... -- PACKAGE@VERSION`、`add go ... -- MODULE@VERSION`，uv 使用 run 的 add。

npm 使用现有 package-lock 的 ci；pip 使用项目 .venv/requirements.txt；uv 使用所选 Python 与 uv.lock 或 requirements；Go 下载并验证模块。冲突 venv 保留。uv 需已有精确 KAI_UV_VERSION，禁止隐式下载 Python。SDK 安装不属于依赖操作。

`KAI_DEP_ACCELERATION=required` 仅给当前进程提供已存在 ks-cli 的设置；不安装网关、不改全局配置、不关闭 TLS/hash/sumdb。回执的 functionalValidation=not-run 明确表示未验证项目功能；依赖事务完成不能冒充项目运行成功。
