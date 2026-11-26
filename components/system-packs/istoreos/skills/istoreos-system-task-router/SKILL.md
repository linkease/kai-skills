---
name: istoreos-system-task-router
description: 按调用者明确选择的范围查询 iStoreOS 设备事实；历史 ID 保留，不再进行任务分流。
owner: system-pack/istoreos
systems: istoreos
triggers: iStoreOS, 路由器问题, 系统问题, 帮我检查, 帮我修复, 不知道怎么办, 不确定, 报错, 异常, 执行这个 .run 文件
auto-use: suggest
needs-fresh-data: true
cost: low
resource-discovery: explicit
---

`sh scripts/observe.sh SCOPE [SUBJECT]` 读取明确范围的系统、网络、存储、服务、包或 Docker 事实；支持范围以脚本参数为准。auto 不再按用户业务意图展开动作，也不选择主技能。

只读观察保留原始来源、未知、冲突和错误；不会执行修复或自动加载其他能力。[代码归属](data/code-ownership.tsv) 是静态索引，不是设备事实。模型可直接使用本能力、其他能力、多个能力或通用工具。没有专用 skill 不代表任务无法处理。
