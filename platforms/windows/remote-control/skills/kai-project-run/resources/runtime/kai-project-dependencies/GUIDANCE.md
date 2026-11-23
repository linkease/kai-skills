---
name: kai-project-dependencies
description: 在所选 mise SDK 和项目隔离环境中安装 npm、pip、uv、Go 依赖。
owner: system-pack/common
systems: ubuntu, debian, istoreos, openwrt, linux, macos, windows
triggers: pip install, npm install, npm ci, go mod, uv sync, Python 依赖, 项目依赖, 验证 Python 依赖安装流程
negative-triggers: 安装 Python, 安装 Node, 安装 Go, 系统软件包
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

在实际目标准备 Bash/full jq，先用 kai-dev-environment 验证精确 SDK；保留项目的 npm/pip/uv/Go 管理器和锁格式，系统库走 kai-software。

`bash scripts/dependencies.sh install MANAGER RUNTIME_VERSION PROJECT`：已有项目中，npm 用现有 package-lock 的 ci；pip 用项目 .venv/requirements.txt；uv 用选定 Python 与 uv.lock 或 requirements；Go 下载并验证模块。已有冲突 venv 保留。脚本每次重新进入 SDK，Windows 使用原生 Node/npm JS 与 Scripts/python.exe，避免批处理参数变形。

`run MANAGER VERSION PROJECT -- ARGS...` 传递原生参数；明确变更可用 `add npm ... -- PACKAGE@VERSION`、`add go ... -- MODULE@VERSION`，uv 用 run 的 add。Python 按项目锁流程修改，不用环境 pip freeze 覆写。uv 需预先安装精确 `KAI_UV_VERSION`，禁止其自行下载 Python。

`sources MANAGER VERSION PROJECT` 仅读取来源提示；Git、私有库和直链需按实际来源处理，不把注册表路由当作所有下载覆盖。

显式加速 `KAI_DEP_ACCELERATION=required` 复用已有 ks-cli 的 Doctor/Explain，只给当前进程提供设置，不安装网关或改全局配置；失败保留退出码，不关闭 TLS/hash/sumdb。安装收据的 functionalValidation=not-run，必须执行/导入实际项目、检查锁和预期输出后报告完成；加速声明另需本次网关证据。
