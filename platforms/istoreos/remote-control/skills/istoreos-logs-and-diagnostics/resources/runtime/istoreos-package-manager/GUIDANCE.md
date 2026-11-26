---
name: istoreos-package-manager
description: 兼容旧 ID 的明确接口；公共能力为 kai-software，不执行任务分流。
owner: system-pack/istoreos
systems: istoreos
alias-for: kai-software
needs-fresh-data: true
invocation: manual
auto-use: off
resource-discovery: explicit
---

兼容标识对应 `kai-software`。Legacy package.sh retains source-qualified native package actions. ensure_services_from_pkg.sh now accepts an explicit service.apply request; no package-wide service selection.

原生事实、错误和接口效果保留；公共实现保持唯一来源。兼容映射不要求模型加载或优先使用另一技能。
