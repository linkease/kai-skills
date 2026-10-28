---
name: istoreos-docker-basics
description: 检查、安装、启停和排查 iStoreOS Docker/dockerd 与容器；镜像或文件下载慢由下载加速能力处理，数据目录迁移由专用 skill 处理。
owner: system-pack/istoreos
systems: istoreos
triggers: Docker 异常, Docker 安装, Docker 启动失败, dockerd, 容器异常, compose, 容器服务
negative-triggers: Docker 镜像慢, Docker 拉取失败, docker pull, Docker 数据目录, data_root
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
---

# iStoreOS Docker Basics

目标：确保 `docker` + `dockerd` 在 iStoreOS 上可用。

## 流程

1) 检测安装：`command -v docker; command -v dockerd`
2) 检测服务：`/etc/init.d/dockerd status || ps w | grep -E '[d]ockerd'`
3) 安装/修复（走 iStoreOS 路径）：优先 iStore meta，其次 `is-opkg/opkg`（不要 apt/yum/systemctl）
4) 启用启动：`/etc/init.d/dockerd enable && /etc/init.d/dockerd restart`
5) 验证闭环（至少 2 条）：`docker version`（含 Server）/ `docker info` / `docker ps`
6) 安装/升级 Docker 类应用前的空间检查（关键）
   - `SKILLS_DIR="${KAIPLUS_SKILLS_DIR:-${KAIPLUS_HOME:?KAIPLUS_HOME is required}/config/skills}"; sh "$SKILLS_DIR/istoreos-docker-basics/scripts/check_space.sh"`
   - 若输出 `need-confirmation:`（例如 DockerRootDir 可用空间 < 2GiB，或 data_root 在 `/overlay/upper/opt/docker`），先处理空间/迁移 data_root 再继续安装镜像/容器
   - 迁移 data_root 属于危险写操作：转 `istoreos-docker-data-root-migrate`（必须明确征得用户同意，并先备份再改）
7) 任何可能拉镜像的动作（`docker pull/build/run`）前置：先跑加速闭环
   - `SKILLS_DIR="${KAIPLUS_SKILLS_DIR:-${KAIPLUS_HOME:?KAIPLUS_HOME is required}/config/skills}"; sh "$SKILLS_DIR/istoreos-docker-acceleration-istoreenhance/scripts/ensure_ready.sh"`
   - 若输出 `need-confirmation:`（例如未安装或 `cache` 未配置），先按提示完成并等待用户确认，再继续 Docker 动作
8) 镜像拉取失败（超时/连接重置/TLS 握手超时等）：
   - 不要直接进入“换源/代理/证书”泛化建议；优先回到第 6 步，确保 `istoreenhance/kspeeder` 真正生效
9) 仍失败时转 `istoreos-logs-and-diagnostics` 收集 `logread` + `uci show dockerd` + `uci show istoreenhance`
