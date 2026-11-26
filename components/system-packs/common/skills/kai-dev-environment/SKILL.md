---
name: kai-dev-environment
description: 查询、安装、验证和执行明确选择的 mise SDK 或 uv；保留精确版本、来源和原生错误。
owner: system-pack/common
systems: ubuntu, debian, istoreos, openwrt, linux, macos, windows
triggers: 安装 Python, 安装 Node, 安装 node, 安装 Go, 安装 golang, 开发环境, 安装开发 CLI, SDK, python-build, 解释器异常
negative-triggers: pip install, npm ci, go mod, uv sync
auto-use: suggest
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

`bash scripts/runtime.sh resolve RUNTIME SELECTOR` 查询目录；`probe RUNTIME VERSION` 查询指定版本。`install RUNTIME VERSION [none|project|global]` 安装精确版本，选择范围默认 none；project/global 会改变对应选择。`verify RUNTIME VERSION` 验证 SDK；`exec RUNTIME VERSION -- COMMAND...` 在该 SDK 执行明确命令。

`bash scripts/dev-cli.sh probe|install|exec uv VERSION [-- ARG...]` 是已支持的开发 CLI 接口。`diagnose.sh LOG_FILE ORIGINAL_EXIT_CODE` 返回标记为启发式的日志证据，不重试安装。

SDK 验证不等于项目成功。Python 使用预编译发布物；缺发布物不隐式装编译器。TLS、签名和 Go 校验保留。`KAI_RUNTIME_ACCELERATION=required` 显式使用既有网关，不启动网关或直连重试；`KAI_GO_GIT_METADATA=required` 仅作用于公共 Go Git 元数据的进程环境。[Python crypto 适配](data/python-openssl.md) 不修改系统 crypto/CA 或覆盖用户 OPENSSL_CONF。
