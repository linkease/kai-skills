# 软件任务规则

维护源为本目录的 Bash 模块。`task.sh OPERATION REQUEST.json` 在已选目标执行，
`ZSETUP_TASK_TARGET_ID` 必须与请求 targetId 一致；连接和凭据由调用方管理。
运行需要 Bash、完整 jq；首次引导继续使用既有安装器。

协议 software-task/v1：stdout 单个 JSON，进度和原生诊断到 stderr。
退出 0 success，20 needs-ai，21 blocked，22 failed，2 invalid；nativeExitCode
保留实际子程序退出码。查询和计划只读，应用必须绑定计划，不自动启动服务。
未知规则不猜下载地址，不将网络、完整性、权限错误解释成无软件候选。

本模块由 kai-skills 以精确摘要的 owner 资源消费，不新增下载器或 zsetup 核心命令。
已有业务一键入口和公开字节保持原接口，逐项通过适配纳入机器任务。


Docker 静态站点配方：`method: "container"`、`software: "nginx-static"`。
`container` 明确给出 `image`（本模块核验的官方 manifest 摘要）、已有持久
`baseDir`、`dataBytes`、`start: true`。`source` 可选 `official` 或
`linkease-mirror`；镜像站仍使用相同内容摘要，不在失败时偷偷改来源。
计划列出真实 daemon 身份/磁盘、架构、512 MiB 镜像展开与保留预算、数据预算、
普通用户 101:101、只读根及数据卷、独立归属 bridge、健康检查和回退限制。
应用是无状态静态站点；端口在宿主机 127.0.0.1 动态分配，更新可能改变端口。
程序返回实际 endpoint；不据此承诺公网访问或数据库一致性。

仅下载缺失镜像时要求 zsetup0.5+ 的 capture（180 秒、1 MiB 输出上限），
Docker 负责 OCI 摘要校验。计划只读；执行须传入原 `details` 为 `plan`。
更新先启动候选并 HTTP 验证，再切换名称并停止/保留旧实例；健康失败保留旧实例。
`intent: "remove"` 的新计划只删除精确归属的容器和独立网络，保留镜像、配置和数据。
不得将此无状态配方用于数据库迁移；需要数据回退时另走真实备份恢复流程。

模块验收：在已核验的持久文件系统下设置 TMPDIR，并设置
`ZSETUP_TEST_NATIVE=/absolute/verified/zsetup`，执行
`python3 -m unittest discover -s software/tests`；容器进程测试使用真实
zsetup 控制私有假 Docker 子进程。原生 Docker 生命周期证据由消费者保存。


本地构建产物使用 `method: "artifact"`，明确 software、version、prefixBase 和
artifact.path/sha256/platform/verifyArgs/expectedOutput。计划仅哈希候选文件，
不猜来源或执行产物；apply 在私有暂存区再次校验，并按明确参数执行自检。
目标传输负责整个前台进程树的截止时间和取消。自检通过后才写不可变版本，
原子替换用户选定数据目录内的命令和 current.json；失败保持旧命令。
不同摘要不能复用同一版本。卸载前完整校验归属和摘要，保留用户文件与小型
版本归属回执，使同摘要重装仍可验证；不覆盖外来 prefix、命令或符号链接。


原生包卸载使用 `intent: "remove"` 和明确的包管理器计划。计划绑定原生已安装
版本；执行仅调用该管理器的 remove/uninstall，再查询确认该包已不在该管理器中。
已不存在的包返回 native-package-already-absent，不会安装仓库候选。移除不使用
purge、强制依赖删除或额外 autoremove；配置/用户数据仍受原生包及其 hooks 策略
约束，不宣称移除了其他来源的同名程序。需要保护的数据应在本次操作计划中备份。

`method: "native-package"` 的 query 读取包注册与仓库候选，不执行程序，
功能状态为 not-run。install 优先复用符合版本的已注册包，不隐式升级；无法
识别其业务自检时返回 installed-functional-check-required，交给 AI 验证。
要求升级时应明确选择新的精确版本。verify 同时核验原生注册和已有功能规则。

`method: "release"` 使用应用目录维护的固定发布配方；当前 Linkspace
0.2.0-sim.3 提供四个平台的 backup-file-level。它是 Kai 工具命名空间的
显式候选，未改变全局 Linkspace stable 或旧 0.1.0 安装器。
`software/build-release-lock.py --check` 核验生成锁与应用源一致。
使用 version、prefixBase；可选 features。计划固定 HTTPS URL、摘要、大小、
平台和自检参数，复用 artifact 的归属/原子激活/卸载协议。下载由 zsetup
完成并校验；可复用明确的已验证缓存，回执区分缓存与真实下载，不伪称网络通过。
query 校验归属和程序摘要但不执行应用；verify 执行已记录的精确自检。
移除保留数据/配置，重新安装仍可核验原版本归属。
