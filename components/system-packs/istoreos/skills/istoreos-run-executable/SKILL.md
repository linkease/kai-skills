---
name: istoreos-run-executable
description: 分别检查本地文件、下载经过摘要校验的文件，或使用明确 runner 执行选定的本地程序副本。
owner: system-pack/istoreos
systems: istoreos
triggers: .run 文件, 执行 run, 运行安装包, dotrun, 可执行文件安装
auto-use: suggest
needs-fresh-data: true
cost: high
resource-discovery: explicit
---

`sh scripts/inspect.sh LOCAL_FILE` 读取文件信息，不执行文件。`bash scripts/fetch.sh HTTPS_URL ABSOLUTE_DEST SHA256` 只下载及校验，不运行。

`bash scripts/run.sh REQUEST.json` 执行 artifact.execute；参数为 operationId、path、sha256、runner（native|sh|bash|dotrun）、arguments 数组、workingDirectory、timeoutSeconds，外层为 schemaVersion:1、operation、实际 targetId、parameters。执行需要既有授权和宿主私有 KAI_OPERATION_STATE_DIR。

源文件是已有常规文件，摘要必须匹配；执行的是拥有的校验副本。runner 不会自动选择，不 chmod 原文件；native 需已有执行位，dotrun 需已有 is-opkg 且无附加参数。失败不自动改后端或重试。退出零只证明所选进程结果，不证明应用健康或任意脚本的所有副作用；系统恢复点也不自动覆盖外部磁盘、数据库、固件和分区。
