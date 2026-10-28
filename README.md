# Kai / LinkEase Device Skills

为 Ubuntu、Debian、iStoreOS、macOS、Windows 提供软件查询与安装、下载加速、mise 开发环境、项目依赖和软件实际使用入口。仓库按用户最自然的两个问题组织：**是什么设备**，以及 **AI 在设备上运行还是从别处远程控制**。

## 直接告诉 AI

把仓库 URL 和下面一句话发给 Codex、OpenCode 或其他支持 Skills 的 Agent：

```text
请从 https://github.com/linkease/linkease-skills 安装适合“远程控制 iStoreOS”的 skills。
只选择一个匹配的 preset，先 dry-run 告诉我将安装什么，不要安装全部系统。
```

如果 AI 就运行在 iStoreOS 设备上，把引号里的内容改为“在 iStoreOS 上使用”。

共同入口为 `kai-software`、`kai-dev-environment`、`kai-project-dependencies`、
`kai-download-acceleration`、`kai-storage-files`、`kai-tool-bootstrap`。系统适配遵循目标设备事实，
远控主机的系统不决定目标包管理器。Windows 需要 Git Bash；首次引导可用原生 PowerShell，WSL 作为独立 Linux 目标。

Linux 三系统已通过声明范围的真实隔离容器验收；macOS arm64 和 Windows AMD64 已完成原生核心功能实测。
Windows 暂缓 WinGet 下载/安装，已测网关的 npm 审计 POST 仍返回 405；完整桌面发布门禁尚未通过。
详细范围及证据见[多系统完成情况](docs/verification/platform-completion-20261028.md)。
`ks-cli`、网关和 jq 引导的未发布候选须按来源锁使用，不能把本地测试结果当成公开制品已经上线。

## 按设备选择

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

安装器从不默认安装所有平台。若设备或使用方式不明确，它只会要求补充缺少的那一项。

## Kai 与第三方 Agent 的区别

`platforms/*/remote-control` 只服务于自身没有 Target Transport 的第三方 Agent。Kai 已经绑定并探测设备时，会直接选择 `components/system-packs` 中的 canonical 系统包，并使用 Kai 自身的 Transport；即使设备通过 SSH 添加，也不会加载第三方 remote-control preset。

公开架构见 [LinkEase Skills 最终架构](https://github.com/linkease/reasonix-kai/blob/main/docs/kaiplus/LINKEASE_SKILLS_FINAL_ARCHITECTURE.zh-CN.md)。Kai 的 Target、Transport 和会话隔离内部设计保留在 Kai 项目文档中。

## 维护与发布

修改 `components/` 后运行：

```sh
sh tools/generate-platforms.sh
sh tools/verify-generated.sh
sh tools/build-release.sh release
```

每个 release 同时提供 `.tar.gz`、`.zip` 和带 SHA-256/source commit/tree digest 的清单。安装器使用原子目录交换，并在 `.linkease-skills/` 记录所有权；升级或卸载前若发现用户修改，会停止并保留原内容。完整流程见 [`docs/RELEASING.md`](docs/RELEASING.md)。

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
