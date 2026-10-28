---
name: istoreos-luci-recovery
description: 诊断和恢复 iStoreOS LuCI 管理页面打不开、500、空白或登录循环；先只读采证，修改、重启或重装前必须确认。
owner: system-pack/istoreos
systems: istoreos
triggers: LuCI 打不开, LuCI 500, LuCI 空白, LuCI 登录循环, 管理页面打不开, Web 管理异常
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
---

# LuCI Recovery (iStoreOS/OpenWrt)

用于处理“安装插件后 LuCI 异常（打不开/500/空白页/登录循环）”。

## 核心原则

- 先证据：先跑只读诊断脚本再下结论。
- 先软恢复：清缓存 + 重启 `rpcd/uhttpd` 往往就能恢复。
- 能不改 `/usr/lib/lua/luci` 源码就不改：优先重装相关包或回退冲突插件。
- 任何写操作（重启服务/清缓存/重装包/改源码）都需要用户明确确认；重装前强烈建议先做系统全量备份（`istoreos-backup-restore`）。

## 只读诊断（推荐）

- `SKILLS_DIR="${KAIPLUS_SKILLS_DIR:-${KAIPLUS_HOME:?KAIPLUS_HOME is required}/config/skills}"; sh "$SKILLS_DIR/istoreos-luci-recovery/scripts/diag.sh"`

## 软恢复（需确认）

- `SKILLS_DIR="${KAIPLUS_SKILLS_DIR:-${KAIPLUS_HOME:?KAIPLUS_HOME is required}/config/skills}"; CONFIRM_LUCI_SOFT_RECOVERY=YES sh "$SKILLS_DIR/istoreos-luci-recovery/scripts/soft_recover.sh"`

## 重装核心包（需确认，建议先备份）

- `SKILLS_DIR="${KAIPLUS_SKILLS_DIR:-${KAIPLUS_HOME:?KAIPLUS_HOME is required}/config/skills}"; CONFIRM_LUCI_REINSTALL=YES sh "$SKILLS_DIR/istoreos-luci-recovery/scripts/reinstall_core.sh"`

## 定位坏文件归属包（只读）

当 `logread`/浏览器报错里出现具体 Lua 文件路径时，用它定位属于哪个包，并对照 `/rom` 基线：

- `SKILLS_DIR="${KAIPLUS_SKILLS_DIR:-${KAIPLUS_HOME:?KAIPLUS_HOME is required}/config/skills}"; sh "$SKILLS_DIR/istoreos-luci-recovery/scripts/trace_owner.sh" /usr/lib/lua/luci/<path>.lua`

## 生成修复命令候选（只读）

基于“坏文件路径”输出重装/回退的候选命令清单（脚本不执行写操作）：

- `SKILLS_DIR="${KAIPLUS_SKILLS_DIR:-${KAIPLUS_HOME:?KAIPLUS_HOME is required}/config/skills}"; sh "$SKILLS_DIR/istoreos-luci-recovery/scripts/suggest_fix.sh" /usr/lib/lua/luci/<path>.lua`
