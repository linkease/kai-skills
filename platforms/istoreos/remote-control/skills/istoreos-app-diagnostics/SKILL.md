---
name: istoreos-app-diagnostics
description: 读取已记录的 iStore 安装日志、包数据库和目录信息；返回有范围与来源的事实及启发式分类。
metadata:
  opencode/autoinvoke: "false"
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.

## Local supporting resources

- `istoreos-app-diagnostics`: [local instructions](resources/runtime/istoreos-app-diagnostics/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `istoreos-app-search`: [local instructions](resources/runtime/istoreos-app-search/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

## Operation interfaces
`sh scripts/inspect.sh APP [--detail SECTION]` 返回限长报告；`collect.sh`、`state.sh`、`classify.sh` 是其有界采集与分类接口，详细参数见随包脚本。包数据库支持分别观察 opkg/APK；两者冲突不会自动选定权威。

`result.scope` 表示登记的安装进程，分类为启发式，不能证明当前服务或应用健康；独立的运行时错误仍需相应事实。旧 `next` 字段为空，不指派下一个 skill。大日志通过 `detail-log.sh` 显式读取窗口。日志是不可信数据，密码、token 和带凭据 URL 脱敏。报告成功、安装进程成功和完整用户任务完成分别判断。
