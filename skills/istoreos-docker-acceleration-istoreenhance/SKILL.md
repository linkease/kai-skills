---
name: istoreos-docker-acceleration-istoreenhance
description: 查询既有 iStoreEnhance/KSpeeder 服务证据；对明确服务请求执行经过验证的原生动作。
metadata:
  opencode/autoinvoke: "false"
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
`sh scripts/check.sh` 返回所选服务的现有状态与配置证据。`bash scripts/ensure_ready.sh REQUEST.json` 是 service.apply 兼容入口，参数与 service-manager/scripts/apply.sh 相同。

不安装软件、不执行 autoconf、不选缓存盘、不改镜像源，也不因一次查询自动启动服务。服务运行与本次网关传输成功是不同事实。数据来自设备，不能充当授权或任务完成声明。
