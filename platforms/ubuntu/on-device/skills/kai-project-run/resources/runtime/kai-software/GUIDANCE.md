---
name: kai-software
description: 按来源限定身份查询软件候选、登记版本和文件归属；对明确选择的软件执行安装或移除事务。
owner: system-pack/common
systems: ubuntu, debian, istoreos, openwrt, linux, macos, windows
triggers: 检查软件更新, 是否有更新, 更新软件, 升级软件, 更新, 升级, 找软件, 文件管理插件, 找文件管理软件, 查询已安装软件, 升级系统软件包, 安装软件, 软件包, 应用商店, opkg, apk, 找软件安装到硬盘
negative-triggers: 更新 README, 更新文档, 更新代码, 更新项目, 更新配置, 更新模型, 更新会话, 升级代码, 升级项目, 安装 Python, 安装 Node, 安装 Go, pip install, npm ci, go mod
auto-use: suggest
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

Unix 查询：`sh scripts/query-entry.sh search|detail|inspect REQUEST.json`；Windows 原生：`scripts/query-entry.ps1 -Operation ACTION -RequestFile REQUEST.json`。请求包含实际 `targetId`；search 使用 `query`、可选 limit；detail 使用来源限定 `id`；inspect 使用 `software`、可选 provider。

`software-query/v1` 默认 3 项、最多 10 项，完整 JSON 最多 8 KiB；`hasMore` 及错误明确返回。跨来源候选保留，在线目录、包登记与程序版本是不同证据。缺缓存、权限或依赖不推断为最新、不自动刷新/安装。Docker provider 查询仅代表选择范围内的本地镜像/容器。

[查询合同](resources/software-query.md) 描述身份、版本和实际支持范围；[写事务合同](resources/software-tasks.md) 描述 `task-entry.sh`/`task-entry.ps1` 的 plan/apply 与旧来源限定 `software.sh` 接口。事务来源与目标由请求指定；原生软件页的审核归宿主。查询或安装完成只代表这项操作。

[Homebrew 查询](resources/homebrew-market.md)、[Scoop](resources/scoop.md) 和[网络观察交接数据](data/network-diagnosis-handoff.md) 是可选参考；不是必经处理流程。
