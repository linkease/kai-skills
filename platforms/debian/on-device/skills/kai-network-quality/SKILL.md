---
name: kai-network-quality
description: 用已有 FastNet 测量明确端点或网络 profile，返回有预算、来源和不健康事实的观察。
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
`sh scripts/network.sh inspect` 仅查询本地能力；`measure quick|wan|multi|nat|ipv6` 测量所选 profile；`measure lan HOST:PORT [PARALLEL]` 使用明确对端。测量可能占满带宽，需要既有端点/流量预算授权；KAIPLUS_CONFIRMED=1 只是执行标记。

`validate REQUEST.json` 检查请求，`diagnose REQUEST.json` 本身也执行验证并返回诊断；operationId 在 metadata.operationId，字节和时间预算在 budget。二者可独立调用，不要求模型遵循固定次序。[请求例](data/diagnose-request.example.json)、[数据合同](data/install-handoff.md)。

`monitor REQUEST STORE [INTERVAL] [COUNT]` 是有界采样；`history compare --store STORE --before RUN1 --after RUN2 --json` 比较相同环境。`lan-serve HOST:PORT TOKEN_FILE [TTL]` / `lan-test HOST:PORT TOKEN_FILE [PARALLEL] [DURATION]` 使用私有令牌文件，不把令牌放 argv/上下文。

Linux/iStoreOS 需已有兼容 FastNet/full jq/setsid 及 zsetup capture 或 timeout。缺依赖明确报告，不在查询中安装。结果 finding 不健康不等于采证失败；HTTP 状态、TLS、包冲突等保留原始类别。路由侧测量不证明终端 Wi-Fi，不自动修复或重试原安装。
