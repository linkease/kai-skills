---
name: kai-dev-environment
description: 查询、安装、验证和执行明确选择的 mise SDK 或 uv；保留精确版本、来源和原生错误。
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.

## Local supporting resources

- `kai-tool-bootstrap`: [local instructions](resources/runtime/kai-tool-bootstrap/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

Optional tool preparation: `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`
or the separately authorized `ensure TOOL` operation. The native Windows preparation interface is
use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`
through existing native PowerShell. Querying this skill does not install missing tools.

## Operation interfaces
`bash scripts/runtime.sh resolve RUNTIME SELECTOR` 查询目录；`probe RUNTIME VERSION` 查询指定版本。`install RUNTIME VERSION [none|project|global]` 安装精确版本，选择范围默认 none；project/global 会改变对应选择。`verify RUNTIME VERSION` 验证 SDK；`exec RUNTIME VERSION -- COMMAND...` 在该 SDK 执行明确命令。

`bash scripts/dev-cli.sh probe|install|exec uv VERSION [-- ARG...]` 是已支持的开发 CLI 接口。`diagnose.sh LOG_FILE ORIGINAL_EXIT_CODE` 返回标记为启发式的日志证据，不重试安装。

SDK 验证不等于项目成功。Python 使用预编译发布物；缺发布物不隐式装编译器。TLS、签名和 Go 校验保留。`KAI_RUNTIME_ACCELERATION=required` 显式使用既有网关，不启动网关或直连重试；`KAI_GO_GIT_METADATA=required` 仅作用于公共 Go Git 元数据的进程环境。[Python crypto 适配](data/python-openssl.md) 不修改系统 crypto/CA 或覆盖用户 OPENSSL_CONF。
