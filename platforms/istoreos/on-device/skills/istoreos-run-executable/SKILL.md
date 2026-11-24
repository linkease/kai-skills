---
name: istoreos-run-executable
description: 安全检查并执行 iStoreOS 上的本地或 URL `.run` 文件；执行前验证来源、架构、空间和影响范围，并要求明确确认。
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources required by its own workflow.

## Local supporting resources

- `istoreos-download-acceleration`: [local instructions](resources/runtime/istoreos-download-acceleration/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `istoreos-kspeeder-domainfold-fetch`: [local instructions](resources/runtime/istoreos-kspeeder-domainfold-fetch/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `istoreos-mise-runtime`: [local instructions](resources/runtime/istoreos-mise-runtime/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `istoreos-package-manager`: [local instructions](resources/runtime/istoreos-package-manager/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

## Business workflow
# iStoreOS `.run` Executable Handler

当用户拿到一个 `*.run`（本地文件或下载链接）并想执行/安装时，按“先获取 → 先检查 → 判断影响范围 → 再确认 → 再执行 → 再留证据”的统一流程走。

## 安全约束（必须遵守）

- `.run` 视为危险操作：未知来源的可执行文件可能改系统配置/覆盖文件/启动服务/导致系统不可用。
- KAIPlus 中的系统范围写入由设备保护门禁建立 Linkspace 恢复点；如果已经处于有效保护中，不要再次提醒备份。
- `.run` 可能写入外部数据盘、数据库、固件或分区。检查发现超出保护范围时，必须单独说明并确认专项备份或停止执行，不能把系统恢复点说成全覆盖。
- 直接在普通 shell 中执行没有 KAIPlus 自动保护，必须如实说明。
- 先做只读检查，不要上来就 `chmod +x` 或直接运行。

## 只读检查（推荐一键）

- `SKILLS_DIR="${KAIPLUS_SKILLS_DIR:?KAIPLUS_SKILLS_DIR is required}"; sh "$SKILLS_DIR/istoreos-run-executable/scripts/inspect.sh" <FILE.run>`

## 获取（当输入是 URL）

- `SKILLS_DIR="${KAIPLUS_SKILLS_DIR:?KAIPLUS_SKILLS_DIR is required}"; sh "$SKILLS_DIR/istoreos-run-executable/scripts/fetch.sh" -o /tmp/<name>.run <URL>`

## 执行（危险操作，需确认）

- `SKILLS_DIR="${KAIPLUS_SKILLS_DIR:?KAIPLUS_SKILLS_DIR is required}"; CONFIRM_RUN_EXEC=YES sh "$SKILLS_DIR/istoreos-run-executable/scripts/run.sh" <FILE.run|URL> [args...]`

提示：
- 如果用户是在设备的普通 shell 里执行命令：可用 `chmod 755 <FILE.run> && <FILE.run> ...`（或在同目录 `./xxx.run`）。
- 建议先尝试 `--help/--version` 获取参数；执行时把输出保存为日志便于回溯。
- 如果你希望 iStoreOS 记录本次安装并支持后续 `is-opkg unrun` 回滚：不带参数执行时优先使用 `is-opkg dotrun`（脚本会自动拷贝到临时文件，避免 dotrun 删除用户原文件）。
