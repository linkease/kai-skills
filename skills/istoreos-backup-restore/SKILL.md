---
name: istoreos-backup-restore
description: 查询原生恢复能力，或对明确模板、恢复点和不可变预览发起单项 ChangeGuard 操作。
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.

## Local supporting resources

- `istoreos-service-manager`: [local instructions](resources/runtime/istoreos-service-manager/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-system-information`: [local instructions](resources/runtime/kai-system-information/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-tool-bootstrap`: [local instructions](resources/runtime/kai-tool-bootstrap/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

Optional tool preparation: `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`
or the separately authorized `ensure TOOL` operation. The native Windows preparation interface is
use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`
through existing native PowerShell. Querying this skill does not install missing tools.

## Operation interfaces
`sh scripts/check.sh` 只读查询已安装程序、capabilities 和 status；程序存在不证明已有保护点或保护覆盖。

`bash scripts/backup_system.sh REQUEST.json` 执行 `recovery.backup`，参数为 `operationId,templateId,timeoutSeconds`。`bash scripts/restore_system.sh REQUEST.json` 执行 `recovery.restore`，参数为 `operationId,checkpointId,diffId,verificationScope,timeoutSeconds`。verificationScope 为 files 或 files-and-services。请求外层为 schemaVersion:1、operation、实际 targetId、parameters；需要宿主提供的既有授权与私有 KAI_OPERATION_STATE_DIR。

ChangeGuard 原生接口负责模板、设备/仓库校验、过期预览复核、持久任务和 `/tmp` 中的已验证恢复程序。原生 `restore-preview` 产生 diff；`restore-job` 可查询任务。受理不等于完成；外部可达性另行返回，不因文件恢复而推断。旧归档路径参数被拒绝，不自动选择恢复点。保护范围由精确模板确定，外部 Docker 数据不自动在内。
