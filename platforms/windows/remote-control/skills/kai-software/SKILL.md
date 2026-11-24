---
name: kai-software
description: 查询、安装、更新和卸载系统软件；脚本识别平台、软件中心及原来源，返回分层版本和操作结果。
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources required by its own workflow.

## Local supporting resources

- `istoreos-app-diagnostics`: [local instructions](resources/runtime/istoreos-app-diagnostics/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `istoreos-app-search`: [local instructions](resources/runtime/istoreos-app-search/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-tool-bootstrap`: [local instructions](resources/runtime/kai-tool-bootstrap/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

Prepare tools locally with `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`
and its explicit `ensure TOOL` operation when needed. Before Bash exists on Windows,
use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`
through native PowerShell, then the authorized Ensure operation.

## Business workflow
在实际目标查询，保留完整来源 ID。目录留在脚本内部，只把命中事实交给模型；一次查询完成不代表用户的完整任务完成。

宿主已提供原生软件查询绑定时优先复用。其他 Agent 通过已有目标 Transport 执行随包入口：Unix `sh scripts/query-entry.sh ACTION REQUEST.json`；Windows 原生 PowerShell `scripts/query-entry.ps1 -Operation ACTION -RequestFile REQUEST.json`，不预设 Bash/jq 已安装。

- 找软件：`search`，请求 `{"targetId":"<实际目标ID>","query":"<关键词>","limit":3}`。
- 已知身份：`detail`，请求 `{"targetId":"<实际目标ID>","id":"<来源限定ID>"}`。
- 检查版本/更新：`inspect`，请求 `{"targetId":"<实际目标ID>","software":"<实际业务ID>"}`；可指定 provider。

结果为 `software-query/v1`，默认 3 项、最多 10 项，摘要最多 240 个字符、完整 JSON 最多 8 KiB。`hasMore` 表示还有候选，缩小关键词或选择精确 ID；不读取目录文件或脚本实现来代替查询。同名跨来源候选保留，不自动接管来源。查询不安装依赖或刷新源，缺依赖时才用随包准备入口在已有授权内处理。

商店、原生登记与运行程序版本是不同证据；缺缓存、未运行验证、来源不可用分别保留未知，不推断为在线最新或安装异常。Docker 查询需显式 `provider:"docker"`，结果只代表本机镜像/容器，不代表远端软件目录。

只在有具体证据缺口时继续查询。需要实际变更时读 [任务合同](resources/software-tasks.md)，保留原 `task-entry.sh` / `task-entry.ps1` 的 plan/apply 和来源限定 `software.sh` 接口；宿主原生软件页仍由用户审核，不用脚本绕过。查询格式、支持范围和精确 ID 见 [查询合同](resources/software-query.md)。

仅使用 Mac 原生软件提供者时读 [Homebrew 查询](resources/homebrew-market.md)；仅使用 Windows Scoop 时读 [Scoop](resources/scoop.md)。项目 SDK/依赖走对应开发能力。网络传输失败需要进一步诊断时读 [网络交接](data/network-diagnosis-handoff.md)。
