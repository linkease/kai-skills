---
name: kai-software
description: 查询、安装、更新和卸载系统软件；脚本识别平台、软件中心及原来源，返回分层版本和操作结果。
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
确认实际目标和软件身份，保留原包管理器及来源。使用随包脚本取得结构化事实，再根据用户的完整任务决定下一步；脚本动作不是 Agent 工具名。

版本和更新信息通常可用一次 `inspect` 取得，不需要预读平台文档或重新猜测商店接口。商店应用、原生包和运行程序的版本分别解释；一次操作完成不代表完整任务完成。

宿主已有原生软件审核页时，优先使用它提供的目录/审核绑定；查询实际目录和安装状态，保留完整来源 ID，返回 reviewURL/reviewPath 让用户在原软件页审核。诊断会话只读，不改用脚本绕过审核、来源、校验或失败处理。

任务 JSON 的 `software` 为实际业务标识。`inspect` 返回平台、软件中心归属、原生登记和候选版本；复用这些事实，仅在有具体缺口时选择新证据：

- 已确认无需更新：说明版本和来源后结束。`no-update-in-cache` 只说明缓存，不能称在线最新。
- 可变更：用 `plan` 提交原请求、intent 和所需存储/备份信息；展示计划的效果，在已有授权内把原 details 作为任务 JSON 的 plan 交给 `apply`。状态或来源变化需重做计划。
- 未知/受阻/失败：报告已知版本/候选、reason、nativeExitCode、已发生效果和缺口。`needs-ai` 表示不能作出确定判断，不要求全系统巡检。归属不明不接管，建议回原软件中心或实际维护方核实；缺缓存不等于不存在。任务需要进一步定位时，只针对缺口选择新证据，避免重复已知事实或盲目重试。

脚本缺依赖时才使用运行时 `probe`；必要准备走运行时 `ensure`，保留其验证后的路径。查询本身不安装依赖或刷新源。

用已选目标 Transport 调用 `scripts/task-entry.sh inspect REQUEST.json`；Windows 用原生 PowerShell 的 `scripts/task-entry.ps1`，无需先假设 Bash 存在。独立包使用它实际分发的运行时资源。脚本路径属于目标，不在控制端重试远程任务。详细输入仅在需要计划/其他安装方式时读 [任务合同](resources/software-tasks.md)。保留现有 `scripts/software.sh` 来源限定接口。

包登记与功能健康分开报告；写后按用户任务验证。SDK/解释器版本走 kai-dev-environment，项目依赖走 kai-project-dependencies，构建运行走 kai-project-run；不要把它们变成系统软件升级。

For a structured transport failure, follow [network handoff](data/network-diagnosis-handoff.md): validate before authorized diagnosis; retry at most once after comparable verification improves. HTTP 401/403/404, dependencies, architecture, postinstall and integrity errors remain software failures. Ordinary installs do not need a general speed test.
