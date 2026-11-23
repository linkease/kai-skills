---
name: kai-software
description: 按目标系统搜索、查询和安装软件，保留原包管理器与来源。
owner: system-pack/common
systems: ubuntu, debian, istoreos, openwrt, linux, macos, windows
triggers: 检查软件更新, 是否有更新, 找软件, 文件管理插件, 找文件管理软件, 查询已安装软件, 升级系统软件包, 安装软件, 软件包, 应用商店, opkg, apk, 找软件安装到硬盘
negative-triggers: 安装 Python, 安装 Node, 安装 Go, pip install, npm ci, go mod
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

先确认实际目标和软件身份，保留原包管理器及来源。

只读版本/更新问题，宿主提供时调用 `tool:software_query`，传 `request.software`、`finishQuery: true`，并按用户语言选择 `language: zh|en`。这是明确的查询终点：脚本采集事实，宿主生成最终答复并结束本轮，归属不明也会如实报告。仅当这项查询就是用户本轮完整请求时使用；还有安装、修复或其他后续工作时，使用下面的非终结维护流程。

KAIPlus 桌面软件页的目录发现和安装已有独立业务：Windows 优先 `tool:software_catalog`，macOS 优先 `tool:software_market`，通过 `use_capability` 调用并先查看工具合同。查询实际目录/安装状态，保留完整来源 ID；用户选定后返回工具给出的 reviewURL/reviewPath，在原软件页审核执行。诊断会话只读；不改用脚本绕过原审核、来源、校验或失败处理。

多步骤软件维护先调用 `tool:software_inspect`，参数 `request.software` 为实际业务标识。脚本已判断平台、软件中心归属、原生登记和候选版本；不要再用散装命令重做这些检查。查询任务先根据结构化结果答复，按结果行动：

- 已确认无需更新：说明版本和来源后结束。`no-update-in-cache` 只说明缓存，不能称在线最新。
- 可变更：用 `tool:software_plan` 提交原请求、intent 和所需存储/备份信息；展示计划的效果，在已有授权内把原 details 作为 request.plan 交给 `tool:software_apply`。状态或来源变化需重做计划。
- 未知/受阻/失败：报告已知版本/候选、reason、nativeExitCode、已发生效果和缺口，然后结束本次查询。`needs-ai` 表示不能作出确定判断，不要求全系统巡检。归属不明不接管，建议回原软件中心或实际维护方核实；缺缓存不等于不存在。用户要求进一步定位时，只针对缺口选择一项新证据；失败后不改写命令重试。

脚本缺依赖时才用 `tool:software_runtime_probe`；必要准备走 `tool:software_runtime_prepare`，保留其验证后的路径。查询本身不安装依赖或刷新源。

没有这些宿主能力时，用已选目标 Transport 调用 `scripts/task-entry.sh inspect REQUEST.json`；Windows 用原生 PowerShell 的 `scripts/task-entry.ps1`，无需先假设 Bash 存在。独立包使用它实际分发的运行时资源。脚本路径属于目标，不在控制端重试远程任务。详细输入仅在需要计划/其他安装方式时读 [任务合同](resources/software-tasks.md)。保留现有 `scripts/software.sh` 来源限定接口。

包登记与功能健康分开报告；写后按用户任务验证。SDK/解释器版本走 kai-dev-environment，项目依赖走 kai-project-dependencies，构建运行走 kai-project-run；不要把它们变成系统软件升级。

For a structured transport failure, follow [network handoff](data/network-diagnosis-handoff.md): validate before authorized diagnosis; retry at most once after comparable verification improves. HTTP 401/403/404, dependencies, architecture, postinstall and integrity errors remain software failures. Ordinary installs do not need a general speed test.
