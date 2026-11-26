---
name: istoreos-docker-data-root-migrate
description: 验证并复制明确的静止 Docker 数据集到空目标；保留挂载身份、元数据与实际复制结果。
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.

## Local supporting resources

- `istoreos-service-manager`: [local instructions](resources/runtime/istoreos-service-manager/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `istoreos-storage-path`: [local instructions](resources/runtime/istoreos-storage-path/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-system-information`: [local instructions](resources/runtime/kai-system-information/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-tool-bootstrap`: [local instructions](resources/runtime/kai-tool-bootstrap/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

Optional tool preparation: `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`
or the separately authorized `ensure TOOL` operation. The native Windows preparation interface is
use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`
through existing native PowerShell. Querying this skill does not install missing tools.

## Operation interfaces
`sh scripts/plan.sh` 只返回现有 dockerd 配置及运行时证据，不选择源或目标。`bash scripts/apply.sh REQUEST.json` 执行 docker.data.copy，不自动完成整套迁移。

请求含 schemaVersion:1、operation、targetId、parameters。参数为 operationId、source、destination、sourceIdentity、destinationIdentity（或 absent）、destinationParentIdentity、serviceName、endpoint、maxSourceBytes、reserveBytes、timeoutSeconds。路径是物理绝对路径；identity 为 stat 的设备/inode 与文件系统类型/ID。endpoint 明确为所选本地 unix 引擎。需要既有授权、私有 KAI_OPERATION_STATE_DIR、原生 rsync 和有界执行器。

前置条件要求引擎静止、来源及挂载身份仍匹配，目标不存在或为空；非空目标不会合并。复制保留并校验内容、所有者、模式、时间、硬/软链接、ACL、xattr；容量只是预检估计，不是配额预留。失败保留已复制数据及不确定效果，不自动删除或回滚。UCI 等于目标或目录存在均不能证明复制完成。

本接口不启停服务、不修改 UCI、不重写第三方 init；服务/API/数据目录切换是其他明确操作，不能把复制成功当作完整迁移成功。
