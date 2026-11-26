---
name: istoreos-mise-runtime
description: 兼容旧 ID 的明确接口；公共能力为 kai-dev-environment，不执行任务分流。
owner: system-pack/istoreos
systems: istoreos
alias-for: kai-dev-environment
needs-fresh-data: true
invocation: manual
auto-use: off
resource-discovery: explicit
---

兼容标识对应 `kai-dev-environment`。Legacy check/probe/verify/diagnose queries and install/exec interfaces remain concrete SDK operations; no task routing.

原生事实、错误和接口效果保留；公共实现保持唯一来源。兼容映射不要求模型加载或优先使用另一技能。
