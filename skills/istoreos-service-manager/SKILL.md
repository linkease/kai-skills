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

可选 `--json-values true` 为完整且已脱敏的 JSON 对象/数组附加同来源的 `jsonValue`，同时保留 content/output 原文和 untrusted 标记；其他文本及不完整窗口以 jsonValueStatus 区分，不补写字段含义或诊断。解析器缺失/JSON 无效返回 unknown；默认关闭，8KiB 回执上限不变，附加值可能需要缩小所选范围。

原生日志可显式选择 `--sections logs --log-count N --log-pattern REGEX`（两个选择器均可单独使用，N 为最后 1–1000 条消息）。它们直接作为 logread 参数，不解释为 shell；回执记录 `logSelection` 和 `completeHistory:false`。未指定时保留未过滤日志查询；选择后仍受原有时间和字节上限约束，超限返回 unknown，不将部分日志报成完整历史或隐式按服务名过滤。

脱敏后的来源标记 `redacted:true`。包含凭据特征或转义的结构化 JSON 使用已有完整 jq 按字段脱敏，保留同一对象中的其他事实；依次使用显式 `KAI_JQ_BIN`、PATH、目标用户的 `~/.local/bin/jq`，显式选择不兼容时不改用其他程序。缺少解析器或无法安全解析时返回 unknown 和 `REDACTION_UNAVAILABLE`，查询不安装依赖。

独立包中的 jq 准备接口为 `sh resources/runtime/kai-tool-bootstrap/scripts/prepare.sh plan|ensure --tool jq`；安装属于明确的目标变更，ensure 返回的校验路径可通过 `KAI_JQ_BIN` 传入查询。工具准备成功不代表业务成功。

来源文本与执行记录是不同证据：源码包含的分支不表示该分支执行过；采集时间不等于文本中事件的发生时间。不同阶段或范围的值不同，只表示观测差异。回执 effects.completed 表示这项操作已经确认发生的效果（也包括原生请求提交），不等于服务健康；验证失败不会消除该历史效果。

`bash scripts/apply.sh REQUEST.json`（或 ensure.sh 兼容入口）执行 service.apply。外层为 schemaVersion:1、operation、targetId、parameters；参数为 operationId、service、action（start|stop|restart|enable|disable|none）、configName、expectedInitSHA256、expectedConfigSHA256（或 absent）、verification、timeoutSeconds；可选 uci:{key,expectedValue,value}。不推断启用字段或补充动作。

verification.kind 明确为 procd-running|procd-stopped|init-enabled|init-disabled|uci-value。Docker start/restart 则要求 docker-api，并给出 endpoint、expectedEngineId、expectedDataRoot；仅 procd running 不能通过 Docker API 验证。还需原生 procd PID 与 /proc Unix socket 归属证据：所选服务进程或其子进程须在 API 采证前后持有该 endpoint；无法读取、归属不同或身份变化时返回未验证，不操作另一个引擎。

宿主提供既有授权和私有 KAI_OPERATION_STATE_DIR；相同 operationId 只返回历史回执。UCI 在唯一私有包中提交，复核原摘要后原子激活。任何失败都保留 completed/unknown/remaining；不自动 fallback start、不安装、不重写第三方 init。
