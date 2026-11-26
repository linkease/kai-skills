---
name: istoreos-luci-recovery
description: 读取 LuCI 相关服务和文件归属；对明确服务或单个本地 opkg 包执行有界操作。
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
`sh scripts/diag.sh [SERVICE]` 返回只读证据；`trace_owner.sh ABSOLUTE_FILE` 查询原生包归属。兼容 `suggest_fix.sh` 只返回观察，不生成修复处方。

`bash scripts/soft_recover.sh REQUEST.json` 是 service.apply 接口。`bash scripts/reinstall_core.sh REQUEST.json` 执行 package.reinstall，显式参数为 operationId、manager:"opkg"、package、version、artifact、sha256、timeoutSeconds。外层为 schemaVersion:1、operation、实际 targetId、parameters；需要既有授权和私有操作目录。

重装只接受摘要与原生元数据都匹配的本地包；不刷新源、不选一组核心包、不删缓存、不重启服务。其他管理器不被自动替代。包已登记不证明 LuCI/Web/API 可用，副作用与实际验证分别返回。
