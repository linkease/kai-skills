---
name: kai-storage-files
description: 限定路径分析空间与大文件、搜索文件名，核实安装目录的挂载和持久性。
owner: system-pack/common
systems: ubuntu, debian, istoreos, openwrt, linux, macos, windows
triggers: 查大文件, 搜索文件名, 磁盘满, overlay 满, 持久化目录, 空间不足, 空间占用, 文件搜索
negative-triggers: Docker 占满, Docker 数据目录迁移, 找软件安装到硬盘
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

在实际目标执行；`bash scripts/usage.sh space ROOT [LIMIT [SECONDS]]` 排序空间占用，`search ROOT TERM [LIMIT [SECONDS]]` 搜索字面文件名。ROOT 是已有绝对子目录，默认 20 条/30 秒（上限 1000 条/300 秒），Transport 同样设置期限。

支持的 Linux 架构复用已发布 Linkspace；缺程序时从 kai-software 的 `zsetup:linkspace` 准备。`KAI_LINKSPACE_BIN` 指定已有客户端。实时扫描使用 ROOT 外临时目录，空间扫描有 64MiB scratch 上限；`KAI_USAGE_TEMP_DIR` 可选已有可写目录。search 的 path 相对结果 root，即使以 / 开头；space 保留 storagePath。

Windows/macOS 或无已发布映射时，仅读取已有 Python3 的标准库适配；可指定 `KAI_USAGE_PYTHON`。不为只读查询安装 SDK。报告实际 backend（python-stdlib 不等于 Linkspace）、逻辑/分配字节差异和覆盖范围；适配跳过链接、子挂载并限制时间/条目。

`storage ROOT [MIN_FREE_BYTES]` 读取挂载、容量和权限。可用空间不等于持久性；overlay/内存/未知 backing 不作为安装位置，实际写入前仍需复核。Exit11 是部分观察，保留原生错误和缺失范围，不能称完整扫描。清理、删除及持久索引需要单独任务。

`cli probe|install|exec uv VERSION [-- ARG...]` 复用 kai-dev-environment，不改变全局选择；项目依赖使用 kai-project-dependencies。
