---
name: istoreos-download-acceleration
description: 兼容旧 ID 的明确接口；公共能力为 kai-download-acceleration，不执行任务分流。
owner: system-pack/istoreos
systems: istoreos
alias-for: kai-download-acceleration
needs-fresh-data: true
invocation: manual
auto-use: off
resource-discovery: explicit
---

兼容标识对应 `kai-download-acceleration`。Legacy dispatch.sh exposes explicitly selected download/git/dependency actions; Docker pull requires KAI_DOCKER_ENDPOINT. No readiness installation or automatic service start.

原生事实、错误和接口效果保留；公共实现保持唯一来源。兼容映射不要求模型加载或优先使用另一技能。
