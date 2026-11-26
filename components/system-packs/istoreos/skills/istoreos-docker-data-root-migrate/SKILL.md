---
name: istoreos-docker-data-root-migrate
description: 验证并复制明确的静止 Docker 数据集到空目标；保留挂载身份、元数据与实际复制结果。
owner: system-pack/istoreos
systems: istoreos
triggers: Docker data_root, Docker 数据目录, Docker 迁移, Docker 占满 overlay, 容器数据迁移
auto-use: suggest
needs-fresh-data: true
cost: high
resource-discovery: explicit
---

`sh scripts/plan.sh` 只返回现有 dockerd 配置及运行时证据，不选择源或目标。`bash scripts/apply.sh REQUEST.json` 执行 docker.data.copy，不自动完成整套迁移。

请求含 schemaVersion:1、operation、targetId、parameters。参数为 operationId、source、destination、sourceIdentity、destinationIdentity（或 absent）、destinationParentIdentity、serviceName、endpoint、maxSourceBytes、reserveBytes、timeoutSeconds。路径是物理绝对路径；identity 为 stat 的设备/inode 与文件系统类型/ID。endpoint 明确为所选本地 unix 引擎。需要既有授权、私有 KAI_OPERATION_STATE_DIR、原生 rsync 和有界执行器。

前置条件要求引擎静止、来源及挂载身份仍匹配，目标不存在或为空；非空目标不会合并。复制保留并校验内容、所有者、模式、时间、硬/软链接、ACL、xattr；容量只是预检估计，不是配额预留。失败保留已复制数据及不确定效果，不自动删除或回滚。UCI 等于目标或目录存在均不能证明复制完成。

本接口不启停服务、不修改 UCI、不重写第三方 init；服务/API/数据目录切换是其他明确操作，不能把复制成功当作完整迁移成功。
