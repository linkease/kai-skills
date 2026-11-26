---
name: istoreos-storage-path
description: 兼容旧 ID 的明确接口；公共能力为 kai-storage-files，不执行任务分流。
owner: system-pack/istoreos
systems: istoreos
alias-for: kai-storage-files
needs-fresh-data: true
invocation: manual
auto-use: off
resource-discovery: explicit
---

兼容标识对应 `kai-storage-files`。detect.sh returns filesystem observations; probe.sh requires an existing physical directory and creates/removes only its owned temporary probe. No selected/chosen installation path.

原生事实、错误和接口效果保留；公共实现保持唯一来源。兼容映射不要求模型加载或优先使用另一技能。
