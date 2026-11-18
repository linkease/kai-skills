#!/bin/sh
set -eu

root="${LINKEASE_SKILLS_ROOT:-$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)}"
pack="$root/components/system-packs/istoreos"
backup="$pack/skills/istoreos-backup-restore"

fail() { echo "failed: $*" >&2; exit 1; }
contains() { grep -F "$2" "$1" >/dev/null || fail "$1 omitted: $2"; }
rejects() { ! grep -F "$2" "$1" >/dev/null || fail "$1 retained obsolete policy: $2"; }

contains "$backup/SKILL.md" 'ChangeGuard + Linkspace'
contains "$backup/SKILL.md" '已经处于有效保护中'
contains "$backup/SKILL.md" '不要重复提醒备份'
contains "$backup/SKILL.md" '明确要求全量备份'
contains "$backup/SKILL.md" '从 iStoreOS UI 手动触发'
contains "$backup/scripts/backup_system.sh" 'CONFIRM_FULL_SYSTEM_BACKUP'

run="$pack/skills/istoreos-run-executable/scripts/run.sh"
rejects "$run" 'CONFIRM_BACKUP_DONE'
rejects "$run" 'CONFIRM_BACKUP_SKIPPED'
contains "$run" 'CONFIRM_RUN_EXEC'

router="$pack/skills/istoreos-system-task-router/SKILL.md"
contains "$router" '明确备份、恢复、回滚或重置请求'
contains "$router" '普通升级和危险修改仍由所属业务 Skill 处理'

for path in \
  "$pack/skills/istoreos-service-manager/SKILL.md" \
  "$pack/skills/istoreos-luci-recovery/SKILL.md" \
  "$pack/skills/istoreos-run-executable/SKILL.md" \
  "$pack/skills/istoreos-docker-data-root-migrate/SKILL.md" \
  "$pack/skills/istoreos-systools/SKILL.md"; do
  rejects "$path" '先做系统全量备份'
  rejects "$path" '先做一次系统全量备份'
  rejects "$path" '先备份再'
done

echo 'ok: iStoreOS defaults to KAIPlus protected Linkspace recovery points and keeps full backup explicit'
