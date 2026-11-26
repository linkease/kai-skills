---
name: istoreos-service-manager
description: 读取 init、UCI、生成配置、procd、日志和文件归属；执行有明确前置状态与后置验证的单项服务操作。
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.

## Local supporting resources

- `kai-system-information`: [local instructions](resources/runtime/kai-system-information/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-tool-bootstrap`: [local instructions](resources/runtime/kai-tool-bootstrap/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

Optional tool preparation: `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`
or the separately authorized `ensure TOOL` operation. The native Windows preparation interface is
use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`
through existing native PowerShell. Querying this skill does not install missing tools.

## Operation interfaces
`sh scripts/inspect.sh --target-id ID --service NAME --sections init,config,runtime,logs,ownership` 读取所选范围。大文件可指定 `--file PATH --offset N --length N`；hasMore、未知、权限错误、超时和不可信原文保留。查询从不执行被检查的 init 脚本。

`bash scripts/apply.sh REQUEST.json`（或 ensure.sh 兼容入口）执行 service.apply。外层为 schemaVersion:1、operation、targetId、parameters；参数为 operationId、service、action（start|stop|restart|enable|disable|none）、configName、expectedInitSHA256、expectedConfigSHA256（或 absent）、verification、timeoutSeconds；可选 uci:{key,expectedValue,value}。不推断启用字段或补充动作。

verification.kind 明确为 procd-running|procd-stopped|init-enabled|init-disabled|uci-value。Docker start/restart 则要求 docker-api，并给出 endpoint、expectedEngineId、expectedDataRoot；仅 procd running 不能通过 Docker API 验证。

宿主提供既有授权和私有 KAI_OPERATION_STATE_DIR；相同 operationId 只返回历史回执。UCI 在唯一私有包中提交，复核原摘要后原子激活。任何失败都保留 completed/unknown/remaining；不自动 fallback start、不安装、不重写第三方 init。
