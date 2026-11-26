---
name: istoreos-system-task-router
description: iStoreOS 用户问题的轻量分流与未知问题回退入口；任务含糊、跨多个子系统或没有明显专用 skill 时，选择一个主能力并从最小只读证据开始。
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources required by its own workflow.

## Local supporting resources

- `istoreos-package-manager`: [local instructions](resources/runtime/istoreos-package-manager/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `istoreos-service-manager`: [local instructions](resources/runtime/istoreos-service-manager/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-system-information`: [local instructions](resources/runtime/kai-system-information/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-tool-bootstrap`: [local instructions](resources/runtime/kai-tool-bootstrap/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

Prepare tools locally with `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`
and its explicit `ensure TOOL` operation when needed. Before Bash exists on Windows,
use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`
through native PowerShell, then the authorized Ensure operation.

## Business workflow
根据实际 iStoreOS 目标和用户意图选一个主能力；明确的软件维护直接走 kai-software，不先做全系统检查。

容器、服务、LuCI、存储、网络、备份、系统设置和未知可执行文件，按目录描述选择对应业务技能。Docker 数据目录迁移使用专用迁移能力；SDK/解释器走 kai-dev-environment，项目依赖走 kai-project-dependencies，具体下载链路走 kai-download-acceleration。

问题含糊时，在目标上运行 `sh scripts/observe.sh <auto|network|storage|service|package|docker|kai> [subject]`，只选相关模式。该小脚本返回限长脱敏事实；用它形成可验证的原因，再按缺口加载辅助能力，不预读全部文档或重复探测。源码问题先查 `data/code-ownership.tsv` 对应行；仓库资料不能代替设备状态。

普通升级由所属业务处理；首次写入保护交给 KAIPlus 门禁。明确的备份/恢复请求再走 istoreos-backup-restore。沿用已有授权与审批，写后验证实际效果。
