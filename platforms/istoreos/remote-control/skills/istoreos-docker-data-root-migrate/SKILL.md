---
name: istoreos-docker-data-root-migrate
description: 安全规划并迁移 iStoreOS Docker data_root；用于 Docker 占满 overlay、数据目录放错磁盘或用户明确要求迁移，执行前必须确认并保留回滚路径。
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources required by its own workflow.

## Local supporting resources

- `istoreos-storage-path`: [local instructions](resources/runtime/istoreos-storage-path/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

## Business workflow
# Docker data_root Migration (Safe)

目标：当 Docker 数据目录在 `/overlay`（例如 `/overlay/upper/opt/docker`）或空间不足时，把 `dockerd.globals.data_root` 迁移到数据盘，避免把系统盘打满。

## 安全约束（必须遵守）

- 不要“自动修改用户 Docker 数据目录”。只有用户明确回复确认（例如“确认迁移”）后才执行写入/迁移。
- 强烈建议迁移前先做一次系统全量备份：转 `istoreos-backup-restore`。
- 所有写操作先备份（带时间戳），并输出回滚命令。
- 迁移前必须停止 `dockerd`，迁移后必须验证 `docker info` 的 `Docker Root Dir` 与 `df` 空间。

## 快速检查（只读）

- `SKILLS_DIR="<absolute-parent-of-this-skill-directory>"; sh "$SKILLS_DIR/istoreos-docker-data-root-migrate/scripts/plan.sh"`

## 执行迁移（写操作，需确认）

- `SKILLS_DIR="<absolute-parent-of-this-skill-directory>"; CONFIRM_DOCKER_DATA_ROOT_MIGRATE=YES sh "$SKILLS_DIR/istoreos-docker-data-root-migrate/scripts/apply.sh" <NEW_DATA_ROOT>`

提示：
- `<NEW_DATA_ROOT>` 建议在数据盘上，例如 `/mnt/<disk>/docker`。
- 若你只知道“要放到哪个盘”，可先用 `kai-storage-files` 选出 `base path`，再拼接子目录。
