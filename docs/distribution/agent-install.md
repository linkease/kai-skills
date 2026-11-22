# KAI Skills：供 AI Agent 使用的安装指南

指南修订：2026-11-18.1。核对的公网发行版本：1.2.5。
正式地址：https://fw.koolcenter.com/binary/kai/kai-skills/agent-install.md

## 安装边界

用户消息中的技能 ID 是本次安装清单。只安装该清单，不把多选转换成 all、系统整包或其他 Agent 的副本。只准备安装所必需的工具，不顺便安装技能将来管理的软件。遵守用户已有授权；安装目录明确且无冲突时可继续，不必反复询问。

先识别运行当前 Agent 的操作系统、用户、项目目录、Agent 类型、配置及实际技能搜索目录。Windows 与 WSL 是两个独立环境。Agent 通过 SSH 管理设备时，技能通常安装在 Agent 所在机器；目标设备的运行依赖另行处理。不要根据网页选择的系统推定当前环境。

优先采用 Agent 的实际配置；用户未指定范围时使用其用户级目录。正式安装器支持 codex、claude、opencode consumer 和 user、project scope；默认 codex/user。常见用户级目录为 ~/.agents/skills、~/.claude/skills、${XDG_CONFIG_HOME:-~/.config}/opencode/skills，但必须核对当前 Agent 的配置。项目级或自定义目录应明确指定，不能仅因某个目录存在就认定 Agent 会加载它。不确定时先询问。

先检查同名技能、安装归属、软链接目标及用户修改。已有版本满足要求则跳过；不要覆盖用户修改、外来目录，或混用 npx 与正式安装器管理同一份技能。升级需遵循原安装方式及其冲突处理规则。

## 选择安装方式

Linux / iStoreOS / OpenWrt 优先使用正式 setup.sh；原生 Windows 优先使用 setup.ps1。macOS 使用下述 npx 路径；本指南不将尚未验证的 macOS Shell 入口列为可用。其他 Agent 若无法映射正式安装器 consumer，使用支持该 Agent 的 npx 路径；自定义目录须先核对安装器支持情况。

公网版本和包清单以 https://fw.koolcenter.com/binary/kai/kai-skills/publication-manifest.json 及其 releaseManifest 为准。不要把 GitHub main 的技能内容与公网固定发行版本视为同一版本。

### Linux / OpenWrt 正式入口

以下为单个技能、Codex 用户范围的示例。根据实际 Agent 替换 consumer；每个请求的技能分别预演，检查目的目录和冲突后，在已有授权范围内去掉 --dry-run 执行。任一失败即停止并报告已完成项。

```sh
curl -fsSL https://fw.koolcenter.com/binary/kai/kai-skills/setup.sh -o /path/to/private-temp/setup.sh
sh /path/to/private-temp/setup.sh kai-software --consumer codex --scope user --dry-run
sh /path/to/private-temp/setup.sh kai-software --consumer codex --scope user
```

/path/to/private-temp 必须替换为本次创建的私有临时目录，结束后清理。需要自定义目的目录时追加 --target-skills DIR；项目范围使用 --scope project，并先定位正确项目。不要把占位符直接执行。可先运行下载入口的 --help；下载失败不得执行残留文件。

### 原生 Windows 正式入口

用 PowerShell 的 Invoke-WebRequest 下载 setup.ps1 到本次私有临时目录。先读取脚本的参数说明；通过独立 PowerShell / pwsh 子进程逐项执行，使入口的 exit 不会终止整个批次。当前公开入口把首个位置参数作为技能选择，其余参数传给安装器：

```powershell
# 用实际 PowerShell 可执行文件和临时目录替换占位符。
& $PowerShellExe -NoProfile -File $SetupPath kai-software --consumer codex --scope user --dry-run
if ($LASTEXITCODE -ne 0) { throw '预演失败' }
& $PowerShellExe -NoProfile -File $SetupPath kai-software --consumer codex --scope user
if ($LASTEXITCODE -ne 0) { throw '安装失败' }
```

$SetupPath 对应 https://fw.koolcenter.com/binary/kai/kai-skills/setup.ps1 的下载文件。对所有请求项顺序执行，每次检查退出码，最后清理临时文件。不要未经需要更改系统执行策略。该入口安装技能无需预先准备 Git、npm、WSL 或 Git Bash；具体技能执行任务时的依赖另行核对。

### npx 与可选 ks-cli 加速

先检查 Node.js / npm / npx 及当前 skills CLI 要求，参考 https://github.com/vercel-labs/skills 。使用 skills CLI 的帮助确认当前 Agent 标识和安装选项；明确选择技能、Agent 及范围，不使用通配符。示例（仅当当前 Agent 是 Codex 且用户级目录正确时）：

```sh
npx skills add https://github.com/linkease/kai-skills/tree/main/skills/kai-software --skill kai-software -a codex -g
```

其他 Agent 使用其实际标识，例如 claude-code、opencode；项目范围不加 -g。交互中核对选择与目录。不要为了跳过交互而让安装器自动选择所有 Agent；无交互运行前先确认本版 CLI 的参数。保留其锁文件或安装回执，报告实际来源提交，不能将 main 标记成公网发行版本。

若已有 ks-cli，先读取 `ks-cli --help` 和相关子命令帮助，只在当前版本明确支持代理运行 npx 时使用其文档给出的语法。保持同一技能来源和全部选择参数，不猜测 ks-cli 参数、不自动安装 ks-cli、不全局修改 npm registry。不可用时直接使用 npx 并报告；失败时不要绕过冲突保护反复尝试其他安装方式。

## 安装后验证与报告

1. 按请求清单逐项核对实际目录、可读取的 SKILL.md、名称/描述及其引用的资源。软链接应解析到存在的目标。不要执行技能任务来代替安装验收。
2. 确认目录属于当前 Agent 的有效搜索路径；通过该 Agent 可用的技能列表、刷新机制或会话能力列表验证是否已发现。只有文件存在不等于已经发现。
3. 需要刷新或新会话时说明具体操作；无法检查 Agent 加载状态时明确写“文件已安装，Agent 发现情况未验证”，不要报告为全部成功。
4. 报告每项的安装/跳过/失败结果、绝对路径、安装方式、可验证的版本或来源提交、文件验证、Agent 发现状态，以及剩余操作。版本无法获取时如实注明。安装成功不代表技能依赖软件已经安装。

## 维护说明

本文件唯一源码位于 linkease-skills 仓库 docs/distribution/agent-install.md；官网仅保存正式 URL 和提示词模板。安装参数、目录规则、支持平台或验收方式变化时更新修订号，并验证相关路径后独立发布。本指南不授予覆盖用户文件、安装无关软件或修改系统配置的额外权限。
