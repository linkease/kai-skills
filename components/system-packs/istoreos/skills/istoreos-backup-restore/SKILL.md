---
name: istoreos-backup-restore
description: iStoreOS 恢复点、备份与回滚入口；日常变更优先使用 KAIPlus ChangeGuard + Linkspace，系统全量备份仅在用户明确要求时手动执行。
owner: system-pack/istoreos
systems: istoreos
triggers: 恢复点, 备份, 恢复, 回滚, 还原, 全量备份, overlay 备份
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
---

# iStoreOS Backup / Restore

目标：日常变更复用 KAIPlus 的 Linkspace 恢复点；只在用户明确要求时进入独立全量备份或恢复流程。

## 默认策略

- KAIPlus 的普通包升级、配置修改和服务调整由设备保护写入门禁负责：首次写入前由 ChangeGuard 调用 Linkspace 建立并校验本轮恢复点。
- 如果当前会话已经处于有效保护中，复用当前恢复点；不要重复提醒备份、不要再次创建恢复点，也不要把额外备份作为继续条件。
- Skill 不直接调用 Linkspace，不自行选择仓库或伪造保护状态。固定恢复点、会话绑定、浏览器证明和 `check-write` 结果由 KAIPlus/ChangeGuard 判断。
- ChangeGuard 不可用或准备失败时，说明原因并停止危险写入；不能静默改用 `overlay-backup`，也不能声称已有保护。
- 刷写固件、调整分区、应用一致性备份以及系统模板范围外的数据不属于普通恢复点承诺，应单独说明范围和恢复方法。

## 用户主动创建恢复点

- 用户明确说“现在备份”“创建恢复点”时，优先引导到 KAIPlus「设备保护」页面，选择范围并手动创建 Linkspace 恢复点。
- 这类恢复点遵循 KAIPlus 当前的存储、保留、校验和恢复规则，不等于 iStoreOS `overlay-backup` 全量归档。

## 系统全量备份（显式操作）

- 只有用户明确要求全量备份、完整 overlay 归档或离线灾难恢复文件时才进入此流程；默认从 iStoreOS UI 手动触发。
- 全量备份对象是 `/overlay/upper`（沙箱环境还可能包含 `ext_overlay/upper`），数据量大、耗时更长，恢复后可能重启。
- 不要因为普通升级、重装或服务调整自动推荐全量备份。
- 若用户明确要求使用命令行且已经确认目标外部存储，可执行：
  `SKILLS_DIR="${KAIPLUS_SKILLS_DIR:-${KAIPLUS_HOME:?KAIPLUS_HOME is required}/config/skills}"; CONFIRM_FULL_SYSTEM_BACKUP=YES sh "$SKILLS_DIR/istoreos-backup-restore/scripts/backup_system.sh" <DIR>`
- `<DIR>` 必须位于外部存储；挂载点根目录会使用 `<DIR>/istore_backup/`。

## 恢复

- KAIPlus Linkspace 恢复点：从「设备保护」查看范围、差异和记录，确认后执行恢复。
- 只有现有文件确实是 `overlay-backup` 全量归档时，才使用对应的全量恢复流程；不要混用两种格式。
- 命令行全量恢复仍需明确确认：
  `SKILLS_DIR="${KAIPLUS_SKILLS_DIR:-${KAIPLUS_HOME:?KAIPLUS_HOME is required}/config/skills}"; CONFIRM_ISTOREOS_RESTORE=YES sh "$SKILLS_DIR/istoreos-backup-restore/scripts/restore_system.sh" <BACKUP_FILE>`

## 只读检查

- `SKILLS_DIR="${KAIPLUS_SKILLS_DIR:-${KAIPLUS_HOME:?KAIPLUS_HOME is required}/config/skills}"; sh "$SKILLS_DIR/istoreos-backup-restore/scripts/check.sh"`
- 检查只报告 ChangeGuard、Linkspace 和可选全量备份工具是否存在，不创建任何备份。
