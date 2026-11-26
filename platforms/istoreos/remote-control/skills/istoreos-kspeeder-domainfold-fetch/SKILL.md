---
name: istoreos-kspeeder-domainfold-fetch
description: 使用已有本地 KSpeeder 接口映射或下载明确 URL；不安装或自动启动服务。
metadata:
  opencode/autoinvoke: "false"
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.

## Local supporting resources

- `istoreos-download-acceleration`: [local instructions](resources/runtime/istoreos-download-acceleration/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `istoreos-kspeeder-domainfold-fetch`: [local instructions](resources/runtime/istoreos-kspeeder-domainfold-fetch/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `istoreos-mise-runtime`: [local instructions](resources/runtime/istoreos-mise-runtime/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `istoreos-package-manager`: [local instructions](resources/runtime/istoreos-package-manager/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `istoreos-service-manager`: [local instructions](resources/runtime/istoreos-service-manager/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-system-information`: [local instructions](resources/runtime/kai-system-information/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-tool-bootstrap`: [local instructions](resources/runtime/kai-tool-bootstrap/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

Optional tool preparation: `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`
or the separately authorized `ensure TOOL` operation. The native Windows preparation interface is
use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`
through existing native PowerShell. Querying this skill does not install missing tools.

## Operation interfaces
`sh scripts/ksget.sh ...` 提供原生 download 兼容参数，KSGET_MODE 默认 direct；auto/accelerated 是显式选项，allow-start=false。`remap_url.sh URL` 返回已有网关的映射；`fetch_via_domainfold.sh URL curl|wget ARGS...` 使用明确下载工具，不自动换工具。

`check_installed.sh` 查询既有程序；`ensure_running.sh REQUEST.json` 是明确 service.apply 兼容入口，无隐含安装、配置或启动。下载完成、内容校验和当前网关实际提供字节是不同事实；下载不执行文件。[实现事实](data/implementation-evidence.md)、[路由范围](data/advanced-routes.md)。
