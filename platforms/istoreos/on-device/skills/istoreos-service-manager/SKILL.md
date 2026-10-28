---
name: istoreos-service-manager
description: 检查和管理 iStoreOS init.d 服务及对应 UCI 启用状态；用于服务未运行、开机未启动、端口未监听或安装后未生效，不负责 LuCI 核心恢复。
owner: system-pack/istoreos
systems: istoreos
triggers: 服务没启动, 服务启动失败, 服务状态, 开机自启, 端口没监听, 安装后没生效, init.d
negative-triggers: LuCI 打不开, LuCI 500, Docker 数据目录
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
---

# iStoreOS Service Manager

目标：把“已安装但没生效/服务没起来/插件没启用”的问题收敛到一个通用闭环：**init.d + UCI enable flag + 验证**。

当操作会“覆盖写配置/删除文件/影响核心服务”时，先提醒用户可做系统全量备份：转 `istoreos-backup-restore`。

## 一键确保（推荐）

- 先向用户说明目标服务、启用状态变化、短暂中断、验证和回滚方式；确认后执行：`KAIPLUS_CONFIRMED=1 sh "$SKILLS_DIR/istoreos-service-manager/scripts/ensure.sh" <service> [uci_config]`

约定：
- `<service>`：`/etc/init.d/<service>` 的名字；脚本拒绝路径、`..` 和非标识符输入
- `[uci_config]`：默认等于 `<service>`，也可以指定实际 UCI config 名（对应 `/etc/config/<uci_config>`）

## 工作流（手动版）

1) 确认 init 脚本存在：`ls -la /etc/init.d/<service>`
2) 先做 init.d 级别启用与启动：
   - `/etc/init.d/<service> enable`
   - `/etc/init.d/<service> restart`（或 `start`）
3) 再确认“插件是否启用”（UCI）：
   - `test -f /etc/config/<uci_config> && uci -q show <uci_config> | head -n 120`
   - 常见字段（优先级从高到低）：`enabled=1` / `enable=1` / `disabled=0`
   - 如果找不到启用字段：必须打开 `/etc/init.d/<service>` 查证（不要猜）
4) 验证：
   - `/etc/init.d/<service> status || true`
   - `logread | tail -n 200 | grep -iE '<service>|error|fail' || true`
