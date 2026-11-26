---
name: istoreos-backup-restore
description: 查询原生恢复能力，或对明确模板、恢复点和不可变预览发起单项 ChangeGuard 操作。
owner: system-pack/istoreos
systems: istoreos
triggers: 恢复点, 备份, 恢复, 回滚, 还原, 全量备份, overlay 备份
auto-use: suggest
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

`sh scripts/check.sh` 只读查询已安装程序、capabilities 和 status；程序存在不证明已有保护点或保护覆盖。

`bash scripts/backup_system.sh REQUEST.json` 执行 `recovery.backup`，参数为 `operationId,templateId,timeoutSeconds`。`bash scripts/restore_system.sh REQUEST.json` 执行 `recovery.restore`，参数为 `operationId,checkpointId,diffId,verificationScope,timeoutSeconds`。verificationScope 为 files 或 files-and-services。请求外层为 schemaVersion:1、operation、实际 targetId、parameters；需要宿主提供的既有授权与私有 KAI_OPERATION_STATE_DIR。

ChangeGuard 原生接口负责模板、设备/仓库校验、过期预览复核、持久任务和 `/tmp` 中的已验证恢复程序。原生 `restore-preview` 产生 diff；`restore-job` 可查询任务。受理不等于完成；外部可达性另行返回，不因文件恢复而推断。旧归档路径参数被拒绝，不自动选择恢复点。保护范围由精确模板确定，外部 Docker 数据不自动在内。
