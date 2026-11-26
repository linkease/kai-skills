---
name: istoreos-system-task-router
description: 按调用者明确选择的范围查询 iStoreOS 设备事实；历史 ID 保留，不再进行任务分流。
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.

## Local supporting resources

- `istoreos-package-manager`: [local instructions](resources/runtime/istoreos-package-manager/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `istoreos-service-manager`: [local instructions](resources/runtime/istoreos-service-manager/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-system-information`: [local instructions](resources/runtime/kai-system-information/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-tool-bootstrap`: [local instructions](resources/runtime/kai-tool-bootstrap/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

Optional tool preparation: `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`
or the separately authorized `ensure TOOL` operation. The native Windows preparation interface is
use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`
through existing native PowerShell. Querying this skill does not install missing tools.

## Operation interfaces
`sh scripts/observe.sh SCOPE [SUBJECT]` 读取明确范围的系统、网络、存储、服务、包或 Docker 事实；支持范围以脚本参数为准。auto 不再按用户业务意图展开动作，也不选择主技能。

只读观察保留原始来源、未知、冲突和错误；不会执行修复或自动加载其他能力。[代码归属](data/code-ownership.tsv) 是静态索引，不是设备事实。模型可直接使用本能力、其他能力、多个能力或通用工具。没有专用 skill 不代表任务无法处理。
