---
name: istoreos-luci-recovery
description: 读取 LuCI 相关服务和文件归属；对明确服务或单个本地 opkg 包执行有界操作。
owner: system-pack/istoreos
systems: istoreos
triggers: LuCI 打不开, LuCI 500, LuCI 空白, LuCI 登录循环, 管理页面打不开, Web 管理异常
auto-use: suggest
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

`sh scripts/diag.sh [SERVICE]` 返回只读证据；`trace_owner.sh ABSOLUTE_FILE` 查询原生包归属。兼容 `suggest_fix.sh` 只返回观察，不生成修复处方。

`bash scripts/soft_recover.sh REQUEST.json` 是 service.apply 接口。`bash scripts/reinstall_core.sh REQUEST.json` 执行 package.reinstall，显式参数为 operationId、manager:"opkg"、package、version、artifact、sha256、timeoutSeconds。外层为 schemaVersion:1、operation、实际 targetId、parameters；需要既有授权和私有操作目录。

重装只接受与当前已安装版本相同、摘要与原生元数据都匹配的本地包；不刷新源、不选一组核心包、不删缓存、不重启服务。其他管理器不被自动替代。包已登记不证明 LuCI/Web/API 可用，副作用与实际验证分别返回。
