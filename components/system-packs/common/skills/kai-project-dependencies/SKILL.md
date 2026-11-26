---
name: kai-project-dependencies
description: 在指定 SDK、管理器和项目中查询来源或执行依赖操作；保留锁格式和项目隔离。
owner: system-pack/common
systems: ubuntu, debian, istoreos, openwrt, linux, macos, windows
triggers: pip install, npm install, npm ci, go mod, uv sync, Python 依赖, 项目依赖, 验证 Python 依赖安装流程
negative-triggers: 安装 Python, 安装 Node, 安装 Go, 系统软件包
auto-use: suggest
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

`bash scripts/dependencies.sh sources MANAGER VERSION PROJECT` 查询来源；`install MANAGER VERSION PROJECT` 在现有项目中执行相应依赖事务；`run MANAGER VERSION PROJECT -- ARGS...` 执行显式原生参数。明确变更入口有 `add npm ... -- PACKAGE@VERSION`、`add go ... -- MODULE@VERSION`，uv 使用 run 的 add。

npm 使用现有 package-lock 的 ci；pip 使用项目 .venv/requirements.txt；uv 使用所选 Python 与 uv.lock 或 requirements；Go 下载并验证模块。冲突 venv 保留。uv 需已有精确 KAI_UV_VERSION，禁止隐式下载 Python。SDK 安装不属于依赖操作。

`KAI_DEP_ACCELERATION=required` 仅给当前进程提供已存在 ks-cli 的设置；不安装网关、不改全局配置、不关闭 TLS/hash/sumdb。回执的 functionalValidation=not-run 明确表示未验证项目功能；依赖事务完成不能冒充项目运行成功。
