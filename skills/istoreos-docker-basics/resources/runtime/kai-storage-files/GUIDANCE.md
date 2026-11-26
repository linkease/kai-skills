---
name: kai-storage-files
description: 在明确路径查询容量、空间占用和文件名；返回实际后端、范围、错误及持久性证据。
owner: system-pack/common
systems: ubuntu, debian, istoreos, openwrt, linux, macos, windows
triggers: 查大文件, 搜索文件名, 磁盘满, overlay 满, 持久化目录, 空间不足, 空间占用, 文件搜索
negative-triggers: Docker 占满, Docker 数据目录迁移, 找软件安装到硬盘
auto-use: suggest
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

`bash scripts/usage.sh space ROOT [LIMIT [SECONDS]]` 查询空间占用；`search ROOT TERM [LIMIT [SECONDS]]` 搜索字面文件名；`storage ROOT [MIN_FREE_BYTES]` 查询挂载、容量和权限。ROOT 是已有绝对子目录，默认 20 条/30 秒，上限 1000 条/300 秒。

Linux 支持映射使用已有 Linkspace，可由 `KAI_LINKSPACE_BIN` 指定；缺失明确报错。Windows/macOS 或无发布映射时使用已有 Python3 标准库，可由 KAI_USAGE_PYTHON 指定；查询不安装后端。实时扫描在 ROOT 外使用私有临时目录，有 64MiB scratch 上限，KAI_USAGE_TEMP_DIR 可指定已有目录。

结果报告 backend、逻辑/分配字节和覆盖；跳过链接、子挂载并限制时间/条目。search.path 相对结果 root；space 保留 storagePath。Exit11 是部分观察。容量不证明持久性；本能力不选择安装位置、不清理文件或迁移数据。`cli probe|install|exec uv VERSION` 是保留的独立开发 CLI 接口，会按所选动作产生相应效果。
