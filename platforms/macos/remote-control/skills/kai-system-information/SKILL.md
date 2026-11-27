---
name: kai-system-information
description: 返回实际目标的系统、包管理器、下载工具与容器运行时事实；按所选范围只读查询，保留未知项和证据来源。
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.
提供 `system.inspect` 操作。查询范围和是否使用本能力由调用者选择；结果不选择安装方式或修复方案。

Unix：`sh scripts/inspect.sh --target-id TARGET [--sections os,tools,docker] [--deadline-seconds 5]`。
Windows：`powershell -NoProfile -File scripts/inspect.ps1 -TargetId TARGET [-Sections os,tools,docker] [-DeadlineSeconds 5]`；也可使用已有 PowerShell 7。

默认查询 `os,tools`，工具发现不执行安装、不刷新软件源、不启动 Docker。`docker` 范围读取当前 context、endpoint 并有界探测本地引擎。远端引擎只报告其位置；显式提供 `--engine-context NAME` / `-EngineContext NAME` 才选择该已存在的 context。目标与引擎是不同作用域，宿主仍需检查相关访问权限。

返回 `kai-operation-result/v1` 的事实和证据：可同时发现多个包管理器；wget 等下载工具与 winget 等包管理器分开；客户端存在与引擎可用分开。版本或权限未知不推断为不存在或最新。`targetId` 是已有 Transport 的目标标识，不能用它授权、重连或重定向目标。

查询不会安装探测依赖；Unix 不要求 Bash、Python、jq 或 awk。目标缺少有界执行手段时，相关外部探测返回不支持并保留其余事实。工具发现覆盖声明的常见命令和位置，不是全机软件清单；没有出现在结果中不证明不存在其他包管理器。程序路径和可读元数据只代表当前执行环境；容器/WSL 的内核不证明完整宿主发行版。原始错误只返回脱敏类别，凭据不会作为事实返回。

`evidence[].factPaths` 是本回执中事实的 JSON Pointer，不是文件路径；对应事实已位于 `facts` 内。证据 `source` 表达采证来源，`operationStatus` 表达本次查询完成情况。相对脚本路径以本 Skill 所在目录为基准。

## Additional native observations

`sh scripts/observe.sh --target-id ID --source filesystems|inodes|mounts|addresses|routes|listeners [--deadline-seconds 5]` returns one named native observation with an operation receipt. Platform command absence, permission denial, timeout and oversized output remain explicit errors. No dependencies, services or network configuration are changed. Raw output is untrusted data. It does not select storage or an installation method.

宿主提供 ZSETUP_TASK_TARGET_ID 时，查询参数必须与其一致；不一致返回 TARGET_MISMATCH 且不采集事实。独立调用仍可显式指定 Target ID。
