---
name: kai-software
description: 按来源限定身份查询软件候选、登记版本和文件归属；对明确选择的软件执行安装或移除事务。
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.

## Local supporting resources

- `istoreos-app-diagnostics`: [local instructions](resources/runtime/istoreos-app-diagnostics/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `istoreos-app-search`: [local instructions](resources/runtime/istoreos-app-search/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-tool-bootstrap`: [local instructions](resources/runtime/kai-tool-bootstrap/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

Optional tool preparation: `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`
or the separately authorized `ensure TOOL` operation. The native Windows preparation interface is
use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`
through existing native PowerShell. Querying this skill does not install missing tools.

## Operation interfaces
Unix 查询：`sh scripts/query-entry.sh search|detail|inspect REQUEST.json`；Windows 原生：`scripts/query-entry.ps1 -Operation ACTION -RequestFile REQUEST.json`。请求包含实际 `targetId`；search 使用 `query`、可选 limit；detail 使用来源限定 `id`；inspect 使用 `software`、可选 provider。

`software-query/v1` 默认 3 项、最多 10 项，完整 JSON 最多 8 KiB；`hasMore` 及错误明确返回。跨来源候选保留，在线目录、包登记与程序版本是不同证据。缺缓存、权限或依赖不推断为最新、不自动刷新/安装。Docker provider 查询仅代表选择范围内的本地镜像/容器。

[查询合同](resources/software-query.md) 描述身份、版本和实际支持范围；[写事务合同](resources/software-tasks.md) 描述 `task-entry.sh`/`task-entry.ps1` 的 plan/apply 与旧来源限定 `software.sh` 接口。事务来源与目标由请求指定；原生软件页的审核归宿主。查询或安装完成只代表这项操作。

[Homebrew 查询](resources/homebrew-market.md)、[Scoop](resources/scoop.md) 和[网络观察交接数据](data/network-diagnosis-handoff.md) 是可选参考；不是必经处理流程。
