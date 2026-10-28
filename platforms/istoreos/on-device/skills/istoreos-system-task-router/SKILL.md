---
name: istoreos-system-task-router
description: iStoreOS 用户问题的轻量分流与未知问题回退入口；任务含糊、跨多个子系统或没有明显专用 skill 时，选择一个主能力并从最小只读证据开始。
owner: system-pack/istoreos
systems: istoreos
triggers: iStoreOS, 路由器问题, 系统问题, 帮我检查, 帮我修复, 不知道怎么办, 不确定, 报错, 异常, 执行这个 .run 文件
auto-use: suggest
routing-group: system-primary
needs-fresh-data: true
cost: low
---

# iStoreOS System Task Router

Use this skill when an iStoreOS request is ambiguous, spans domains, or has no obvious specialist. It is a router, not a second implementation of each specialist.
Identify the actual target System Pack first. Ubuntu is not iStoreOS: do not apply its opkg/apk, UCI, procd or mise-exec workflow to ordinary Linux.

## Select One Primary Skill

1. "安装/卸载/升级/找软件/应用商店/opkg/apk/mise 插件" -> `kai-software`; detect the actual database/tool before choosing commands.
2. "Docker/容器/dockerd/compose" -> `istoreos-docker-basics`; pull/download failures -> `kai-download-acceleration`.
3. "GitHub/GitLab/HuggingFace/下载链接/git clone/文件下载慢" -> `kai-download-acceleration`.
4. "磁盘满/overlay 满/数据目录/装到硬盘/迁移目录" -> `kai-storage-files`; Docker data-root migration routes to `istoreos-docker-data-root-migrate`.
5. "服务打不开/端口不通/启动失败/开机自启" -> `istoreos-service-manager`.
6. "LuCI/网页管理/登录循环/500/空白页" -> `istoreos-luci-recovery`.
7. "不知道配置字段/不确定脚本行为/要改配置" -> internal helper `istoreos-source-introspect` first.
8. "恢复/重置/升级/危险修改/迁移前" -> `istoreos-backup-restore` first.
9. "网速慢/测速/延迟或抖动/NAT 类型/IPv6 是否可用/局域网测速" -> `istoreos-network-quality`; a specific slow download remains with `kai-download-acceleration`.
10. "修改 IPv6 PD/relay/NAT 模式/硬盘不休眠/iStore 商店损坏/升级后内核模块异常" -> `istoreos-systools`.
11. "安装 Python/Node.js/Go SDK/选择运行时版本/python-build/预编译/解释器异常" -> `kai-dev-environment`; system facts use check.sh, installed SDK checks use probe.sh, installations use install.sh. These dedicated helpers establish integration for each call and report scoped results.
12. ".run 文件/未知可执行安装包" -> `istoreos-run-executable`.
13. "pip install/npm install/npm ci/go mod/依赖下载或安装失败" -> `kai-download-acceleration`; an absent runtime or inactive venv loads mise-runtime as needed. Go SDK and Go modules are separate tasks. System feed packages still use package-manager.

## Loading Budget

- Load only the selected primary skill first.
- Load at most one internal helper at a time, and only when current evidence requires it. Common helpers are `istoreos-app-search`, `istoreos-logs-and-diagnostics`, `istoreos-source-introspect`, and `istoreos-quickstart-api` when a bound LuCI HTTP capability exists.
- Do not load every skill named in a route or preload follow-up skills "just in case".
- Do not expose skill names as choices unless the user asks for implementation details.

## Unknown-Problem Contract

- A missing specialist is not a reason to refuse the task or dump generic advice.
- Start with one bounded evidence card: `sh "$SKILLS_DIR/istoreos-system-task-router/scripts/observe.sh" <auto|network|storage|service|package|docker|kai> [subject]`. Select one mode; do not run all modes.
- The observer is read-only, rejects unsafe identifiers, redacts common credentials, and caps output at 8 KB. Collect more only when the first card supports a falsifiable hypothesis.
- If ownership or behavior remains unclear, load `istoreos-source-introspect`; if a command failed, load `istoreos-logs-and-diagnostics`.
- For development/source questions, read only the matching row in `data/code-ownership.tsv`, then inspect that repository path at its current revision. Repository knowledge is not device evidence.
- Form a falsifiable cause, propose the least invasive next step, and preserve the same confirmation and verification rules used by specialist skills.
- Do not create a new skill during the incident. Add one later only when a workflow recurs and contains non-obvious reusable decisions.

## Safety

Before a write, state target, effects, verification and recovery, then obtain any missing authorization. Reuse already granted authorization for that scope; ask again only for a new effect or product decision. After a write, verify and report current evidence.
