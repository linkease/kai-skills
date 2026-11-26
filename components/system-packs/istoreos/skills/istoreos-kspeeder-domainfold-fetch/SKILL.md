---
name: istoreos-kspeeder-domainfold-fetch
description: 使用已有本地 KSpeeder 接口映射或下载明确 URL；不安装或自动启动服务。
owner: system-pack/istoreos
systems: istoreos
invocation: manual
auto-use: off
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

`sh scripts/ksget.sh ...` 提供原生 download 兼容参数，KSGET_MODE 默认 direct；auto/accelerated 是显式选项，allow-start=false。`remap_url.sh URL` 返回已有网关的映射；`fetch_via_domainfold.sh URL curl|wget ARGS...` 使用明确下载工具，不自动换工具。

`check_installed.sh` 查询既有程序；`ensure_running.sh REQUEST.json` 是明确 service.apply 兼容入口，无隐含安装、配置或启动。下载完成、内容校验和当前网关实际提供字节是不同事实；下载不执行文件。[实现事实](data/implementation-evidence.md)、[路由范围](data/advanced-routes.md)。
