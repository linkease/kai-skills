# Kai / LinkEase Device Skills

为 Ubuntu、Debian、iStoreOS、macOS、Windows 提供按业务选择的独立 skills：软件查询安装、下载加速、mise 开发环境、项目依赖、空间分析和文件查找。可以只安装一个 skill、选择业务集合，或下载某个系统全部适用 skills。

独立目录位于 [`skills/`](skills)，业务索引为 [`business-catalog.json`](business-catalog.json)，精确集合锁位于 [`bundles/`](bundles)。`components/` 是维护源码，不是安装入口。当前业务分发处于 BM0–BM10 实施验收阶段，正式发布状态以[执行记录](docs/verification/business-distribution-execution.md)为准。

## 按业务选择

| 需求 | 独立 skill |
| --- | --- |
| 搜索、查询、安装和使用软件 | [`kai-software`](skills/kai-software) |
| 下载文件、Git、Docker 加速 | [`kai-download-acceleration`](skills/kai-download-acceleration) |
| 使用 mise 安装和选择 SDK | [`kai-dev-environment`](skills/kai-dev-environment) |
| 安装和运行 npm、pip、uv、Go 项目依赖 | [`kai-project-dependencies`](skills/kai-project-dependencies) |
| 查空间、定位大文件、搜索文件 | [`kai-storage-files`](skills/kai-storage-files) |
| 准备 Bash、完整 jq 和内部工具 | [`kai-tool-bootstrap`](skills/kai-tool-bootstrap) |

每个目录都携带自己需要的执行资源，可以直接复制给支持标准 SKILL.md 的 Agent；不要求同时安装其他 Kai skills。目标设备上的 mise、ks-cli 等程序仍需按任务探测和准备。直接复制不建立本仓库安装器的归属记录，后续由复制者管理；使用下列安装器才有受管升级与卸载。

业务集合 `development` 包含开发环境、项目依赖和下载加速；`software-management` 包含软件管理和下载加速。集合是锁定清单，不额外激活一个空壳 skill。

## 直接告诉 AI

把仓库 URL 和下面一句话发给 Codex、OpenCode 或其他支持 Skills 的 Agent：

```text
请从 https://github.com/linkease/kai-skills 安装 kai-download-acceleration。
先 dry-run 告诉我安装目录、版本及冲突；只安装这个业务 skill。
```

开发者可以改为“安装 development 业务集合”。需要系统全部能力时，明确说“安装远程控制 iStoreOS 的全部适用 skills”。单个通用 skill 可以先下载，执行任务前再识别目标系统；远控集合需要明确目标和执行方式。

共同入口为 `kai-software`、`kai-dev-environment`、`kai-project-dependencies`、
`kai-download-acceleration`、`kai-storage-files`、`kai-tool-bootstrap`。系统适配遵循目标设备事实，
远控主机的系统不决定目标包管理器。Windows 需要 Git Bash；首次引导可用原生 PowerShell，WSL 作为独立 Linux 目标。

历史多系统核心功能结果见[多系统完成情况](docs/verification/platform-completion-20261028.md)。
新的独立 skill / 业务集合候选尚未完成多系统验收，最近复测中仍有 iStoreOS Git 软件源校验、macOS Git HTTP 405 和 Windows 引导下载 DNS 问题。
WinGet 实际安装、集合原生旅程及 npm 审计能力尚未通过新候选门禁；当前优先按[代码完成标准](docs/architecture/business-development-completion.md)补齐实现，再集中测试。
`ks-cli`、网关和 jq 引导的未发布候选须按来源锁使用，不能把本地测试结果当成公开制品已经上线。

## 下载某个系统全部适用 Skills

系统集合在本发行版本构建时冻结成员，包含通用业务、系统专属能力，以及远控模式需要的连接 skills。同一个 skill 的内容与独立安装完全相同；系统全量不会展开为所有操作系统。

### Ubuntu / Debian

- [`platforms/ubuntu/on-device`](platforms/ubuntu/on-device) / [`remote-control`](platforms/ubuntu/remote-control)。
- [`platforms/debian/on-device`](platforms/debian/on-device) / [`remote-control`](platforms/debian/remote-control)。

五个系统各有两种模式，共十个预设。

### iStoreOS

- [`platforms/istoreos/on-device`](platforms/istoreos/on-device)：AI 已经在 iStoreOS 设备上运行。
- [`platforms/istoreos/remote-control`](platforms/istoreos/remote-control)：AI 在电脑或另一台主机上，通过 SSH/LuCI 控制 iStoreOS。

每个目录都是自包含安装预设。不要从 `components/` 安装；那里是维护者使用的唯一源码。

### Windows

- [`platforms/windows/on-device`](platforms/windows/on-device)：AI 在 Windows 上运行，原生 PowerShell 引导 Git Bash，技能脚本通过 Bash 执行。
- [`platforms/windows/remote-control`](platforms/windows/remote-control)：AI 通过 Windows OpenSSH + PowerShell 远程控制。

### macOS

- [`platforms/macos/on-device`](platforms/macos/on-device)：AI 直接在 Mac 上运行。
- [`platforms/macos/remote-control`](platforms/macos/remote-control)：AI 在其他设备上，通过 SSH 控制 Mac。

## 安装器

先预演一个 skill、一个业务集合或一个系统全量集合：

```sh
sh install.sh --list-skills
sh install.sh --list-bundles
sh install.sh --skill kai-download-acceleration --consumer codex --dry-run
sh install.sh --bundle development --consumer codex --dry-run
sh install.sh --platform windows --all --mode on-device --consumer codex --dry-run
```

确认预演结果后去掉 `--dry-run`。OpenCode 使用 `--consumer opencode`；其他 Agent 使用 `--consumer generic --target-skills DIR`。也可为任何 consumer 显式指定隔离目的目录。

Windows 没有 Bash 时可先原生预演：

```powershell
./install.ps1 -Action Plan -Skill kai-software -Consumer codex
```

按回执定位受验证的原生 Bash bootstrap；`-Action EnsureBash` 是显式软件准备动作。已有可信 Git Bash 时传入 `-TrustedBash 'C:/Program Files/Git/bin/bash.exe'`，Plan 会继续执行 shell dry-run；Install 才安装技能目录。

受管单装和集合可以共存：卸载集合不会删除仍被单装或其他集合使用的成员。升级、卸载使用与原安装相同的选择和目的目录：

```sh
sh install.sh --skill kai-download-acceleration --consumer codex --upgrade
sh install.sh --bundle development --consumer codex --uninstall
```

共享成员版本变化会列出受影响的选择；明确协调升级时使用 `--upgrade --update-shared`，同步更新这些选择的锁。用户修改、外来同名目录和变更过的软链接保留并报告冲突。旧 preset 首次迁移也会显示在 dry-run 中，完整验证旧内容后才进行事务替换。

下面的旧系统预设命令继续兼容：

Windows 尚无 Bash 时，先解压所选预设，通过原生 PowerShell 执行
`skills/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`；在当前授权范围内
执行 `-Action Ensure`，验证实际 Git Bash 后，再运行下面的 shell 安装器。
远控场景通过目标现有 Transport 执行，不能把目标工具装到控制端。


先查看可用预设：

```sh
sh install.sh --list
sh install.sh --list --json
sh install.sh --describe istoreos-remote-control
```

预演并安装到 Codex：

```sh
sh install.sh --platform istoreos --mode remote-control --consumer codex --dry-run
sh install.sh --platform istoreos --mode remote-control --consumer codex
```

安装到 OpenCode 或明确目录：

```sh
sh install.sh --platform istoreos --mode remote-control --consumer opencode --dry-run
sh install.sh --platform istoreos --mode on-device --consumer generic \
  --target-skills /path/to/agent/skills --dry-run
```

Reasonix 的通用 Skill Store 通过自定义 skills 搜索目录消费相同预设：使用 `--consumer generic --target-skills DIR`，先 dry-run，再将该目录加入 Reasonix 配置的 `[skills].paths`（loader 中的 CustomPaths）。也可选择它实际扫描的项目 `.reasonix/skills` 或 `.agents/skills` 目录。按 Agent 是否在目标设备上运行选择 on-device 或 remote-control；不要把 Ubuntu 控制端当成 iStoreOS 目标系统。仓库的实际 Reasonix loader 测试覆盖两个模式的描述、触发词、系统路由元数据和辅助脚本发现。

Kai 源代码内置的 vendored System Pack/source lock 属于另一条同步流程；设备已安装的 Agent bundle 可按用户授权单独导出替换。iStoreOS 的运行时和依赖合约见 [`docs/architecture/runtime-download-contract.md`](docs/architecture/runtime-download-contract.md)；通用开发能力和平台例外见 [`docs/architecture/multisystem-milestones.md`](docs/architecture/multisystem-milestones.md)。本次实现的命令、结果与未覆盖设备见 [`docs/verification/runtime-download-2026-10-08.md`](docs/verification/runtime-download-2026-10-08.md)；后续授权真机结果与未通过项见 [`docs/verification/runtime-device-2026-10-08.md`](docs/verification/runtime-device-2026-10-08.md)；缓存镜像故障修复与重复实测见 [`docs/verification/runtime-device-followup-2026-10-08.md`](docs/verification/runtime-device-followup-2026-10-08.md)。

安装器从不默认安装所有平台。单 skill 不要求预先选择系统整包；系统全量及远控选择只补充其真正需要的目标信息。

## Kai 与第三方 Agent 的区别

`platforms/*/remote-control` 只服务于自身没有 Target Transport 的第三方 Agent。Kai 已经绑定并探测设备时，会直接选择 `components/system-packs` 中的 canonical 系统包，并使用 Kai 自身的 Transport；即使设备通过 SSH 添加，也不会加载第三方 remote-control preset。

公开架构见 [LinkEase Skills 最终架构](https://github.com/linkease/reasonix-kai/blob/main/docs/kaiplus/LINKEASE_SKILLS_FINAL_ARCHITECTURE.zh-CN.md)。Kai 的 Target、Transport 和会话隔离内部设计保留在 Kai 项目文档中。

## 维护与发布

按业务 skill 独立发布、业务集合及系统全量集合的下一阶段计划见
[业务 Skill 分发实施里程碑](docs/architecture/business-skill-distribution-milestones.md)。
各阶段实施状态见[执行记录](docs/verification/business-distribution-execution.md)。

修改 `components/` 后运行：

```sh
sh tools/generate-business.sh
sh tools/generate-platforms.sh
sh tools/verify-generated.sh
sh tools/build-release.sh release
```

默认构建 31 个独立 skill、2 个业务集合、10 个系统集合的 `.tar.gz` / `.zip`，共 86 个归档，以及来源和 SHA-256 清单。输出目录须不存在，避免混入旧版本。旧的 20 个 preset 兼容归档使用 `sh tools/build-release.sh --legacy OUTPUT`。

独立归档解包后可直接复制 skill；业务/系统归档含离线安装器，复用上面的选择参数。Windows 从集合根目录 `install.ps1 -Action Plan` 开始。受管安装器记录共享归属，升级或卸载前发现用户修改会停止并保留内容。完整构建、验证和下载流程见 [`docs/RELEASING.md`](docs/RELEASING.md)。

旧 `--profile istoreos` 与 `--profile remote-control-istoreos` 命令在迁移期仍可使用，但会输出迁移提示。

## 迁移与维护者同步

四个旧主入口通过别名解析到唯一新入口：`istoreos-package-manager` → `kai-software`、
`istoreos-mise-runtime` → `kai-dev-environment`、`istoreos-download-acceleration` → `kai-download-acceleration`、
`istoreos-storage-path` → `kai-storage-files`。其原生脚本作为受所有权和摘要保护的资源保留；
其余十六个原生技能继续服务 iStoreOS。项目依赖独立进入 `kai-project-dependencies`。
Kai/Reasonix 已实现精确别名解析；其他 Agent 依据包内 `migration.json` 迁移到新 ID，
不能假定其原生识别本项目的 `aliases` 扩展元数据。新安装只激活新主入口。

修改唯一源码后使用 `tools/generate-platforms.sh` 生成分发；Kai 内置同步使用
`python3 tools/sync-kai-system-packs.py --apply`，检查用不带 `--apply` 的同一命令。
该同步只导出 canonical 层，公共六技能保存一次，不携带第三方 Transport。
来源锁记录基准提交、工作树状态及实际内容摘要；未提交候选不能当作发布版本。
详细任务和验收记录见 [`docs/verification/multisystem-execution.md`](docs/verification/multisystem-execution.md)。
