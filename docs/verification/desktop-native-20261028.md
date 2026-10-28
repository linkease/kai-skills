# macOS / Windows 原生补充验收（2026-10-28）

后续三轮专项优化已关闭原 8 项阻塞中的 7 项；本文件保留首次补测历史。最新结果见[专项修复报告](desktop-optimization-20261028.md)。

结论：**部分通过，桌面完整发布门禁未达成**。27 项原生验收记录通过；8 项剩余门禁逐项记录在 [机器可读结果](desktop-native-20261028-results.json)。本轮已结束测试并清理临时网关与转发。

MS0–MS10 原先通过的历史范围保留。本次是用户后续授权的原生补充测试，使用新的 worktree 候选；旧 Linux 制品证据不移用于新桌面制品。不把既有 SDK 复用、离线安装或下载完成等同于首次安装和完整验证通过。

## 任务树与验收标准

| 阶段 | 任务与明确验收标准 | 结果 |
| --- | --- | --- |
| 接入与隔离 | 已有 SSH 信任；数据盘独立目录；真实 Transport；字面参数、中文、空参数、stdin、退出码 37；记录既有工具 | 通过 |
| 工具与软件 | 原生 Bash、完整 jq、mise、系统软件查询；必要工具安装、复用和卸载 | 部分通过；Windows 缺核心时引导失败、WinGet 来源为空 |
| 开发与实际使用 | 冻结 Python 3.13.7 / Node 22.14.0 / Go 1.24.1；pip/npm/Go/uv 项目；Unicode、链接排除、空间查询；不改全局默认 | 部分通过，见平台矩阵 |
| 加速与收尾 | 真实原生客户端与网关下载；原校验不变；新目录重复关键路径；原配置保持；临时资源清理 | Windows Node/Go/npm/Go 模块通过；全平台完整加速仍未达成；清理通过 |

每个修复先在公开 CLI/Transport 边界复现，再修复、自检；同一路径最多三轮优化。Windows pip 三轮仍超时，停止继续修改该路径。

## 实测矩阵

| 能力 | macOS arm64 | Windows AMD64 |
| --- | --- | --- |
| 原生执行环境 | 系统 Bash 3.2.57，已有 Homebrew/mise | PowerShell 5.1，SSH 默认 PowerShell 7.6.3，Git Bash 5.3.15；Bash bootstrap 复用通过 |
| 连接与参数 | SSH、6 类字面参数、stdin、退出码通过 | SSH、UTF-8、param、6 类字面参数、stdin、退出码、真实 cmd 桥接通过 |
| preset 生命周期 | 最终包在新中文目录完成安装、升级、卸载 | 最终包在新中文目录完成安装、升级、卸载 |
| 软件查询 | Homebrew exact mise 查询通过 | 官方 WinGet 模块返回正确 ID、空 Source，适配器拒绝推断来源；未安装/卸载系统包 |
| jq / zsetup | 复用系统完整 jq | 原生 zsetup 0.4.0 下载、大小/SHA256 校验 jq 1.8.2；原安装器安装、功能验证、卸载通过；无核心首次引导仍失败 |
| 冻结 SDK 首次安装 | Python/Node/Go 在线解析失败，未通过 | Node 22.14.0、Go 1.24.1 加速安装与来源验证通过；Python 下载完成，证明验证失败 |
| 已有 SDK 复用 | 隔离 mise 链接既有 Node 24.18.0、Go 1.26.5 并验证通过；Homebrew Python 布局缺 unversioned python，验证拒绝 | 已有 Python 3.14.6 隔离 mise 链接与基础验证通过，不能代替冻结 Python 首装 |
| npm / Go 依赖 | 官方冻结离线输入；is-number 7.0.0 SRI、uuid 1.6.0 go.sum、实际运行通过；无在线加速声明 | 冻结 SDK 下 npm ci、Go 模块验证和运行通过；新项目重复通过；独立核对 Node/Go 真实版本 |
| pip / uv | 缺少可验证选定 Python SDK，在线路径受 DNS 阻塞 | pip 在既有 Python 上三轮超时（含直连），uv 安装 180 秒超时；均未通过 |
| 文件与空间 | APFS、实际挂载点、稀疏分配大小、Unicode 搜索、链接排除通过 | Win32 NTFS 卷查询、Unicode 搜索、reparse 排除通过；扫描明确使用逻辑大小，不声称 NTFS 实际分配量 |
| 系统/服务只读查询 | 系统诊断 JSON 通过；未变更 launchd 服务 | 系统诊断、现有 SSH 服务/eventlog 只读查询通过；未变更服务 |

空间 fixture 固定包含 2 MiB 文件、8 MiB 逻辑长度文件和 4 字节文件，总逻辑大小 10,485,764 字节；外部链接被排除。macOS 的 8 MiB 文件实际分配为 0。Windows 明确报告逻辑大小。

## 修复与回归

1. **Windows SSH 退出状态与 UTF-8**：原脚本 exit 37 被外层默认 PowerShell 归一化为 1。短编码启动器通过 stdin 接收 UTF-8，独立执行原 BOM 脚本并回传每次唯一状态帧；避免整段脚本挤入命令行。保留 param/using/#requires 位置，清理脚本临时文件；未改默认 Shell 或持久执行策略。三轮修正后原生退出码、中文、param、标准错误通过。PowerShell 5.1 的宿主 progress/CLIXML 诊断可能仍出现在 stderr。
2. **macOS APFS 空间事实**：路径前缀匹配误选只读系统根卷，导致可写数据目录被判定不可安装。按查询路径使用原生 df 确认挂载点，用 statvfs 的实际路径标志判断只读。原生公开 usage.sh 回归先红后绿。
3. **Windows 未修改 preset 却无法升级**：原生 jq 的 CRLF 进入 ownership 摘要比较。Windows 安装器统一 jq 二进制输出模式，避免尾部 CR。原生公开安装器先复现误报，修复后新目录安装、升级、卸载通过。

回归测试新增 `tests/multisystem/test_native_macos_storage.py` 与 `test_native_desktop_lifecycle.py`。Windows Transport 在既有公开边界回归中模拟外层状态归一化；缺失状态帧必须返回 255。

## 尚未达成的门禁

- macOS 加速域名与上游 DNS 解析持续超时，账号没有免交互 sudo；未修改系统 DNS/hosts。冻结 SDK 首装及完整在线依赖/加速路径不通过。
- Windows Python 3.13.7 下载 21,614,108 字节后，GitHub attestation API 无法访问。保持验证开启，没有使用错误提示建议的关闭校验选项。
- Windows pip 全入口在既有 Python 3.14.6 上分别运行 240 / 90 / 90 秒均超时；venv 配置、解释器、pip launcher 已存在，尚未定位根因。第三次为直连索引；不能直接归因于加速网络。停止此路径继续优化。
- Windows uv 0.8.22 的公开安装入口超时，没有完成 receipt；未把已有 Python 或下载进度算作安装成功。
- 官方 Microsoft.WinGet.Client 1.29.380 签名有效，但本机 `PSFoundCatalogPackage` 的 Source 为空，适配器返回 no-unique-candidate；保留来源保护。
- Windows 同时缺 jq 与 zsetup 时，公共 jq ensure 仍进入 Linux/Darwin 核心引导并失败。已有受信任原生核心的 owner 生命周期已通过，两者分开验收。
- Homebrew Python 的布局不满足现有 mise 链接执行入口，不能用该复用替代 macOS Python SDK 门禁。

未测试其他桌面架构、桌面 Docker daemon/镜像拉取、真实 Codex/OpenCode 应用、原生服务变更。桌面没有 Docker；没有安装桌面 Docker 或启动常驻服务。

## 候选、证据与验证

最终候选在 `release/desktop-native-final-candidate`，20 个制品，sourceState 为 **worktree**，不是已发布版本。本机证据在被忽略的 `release/desktop-native-evidence`；目标配置、信任文件、密钥和原始设备日志留在仓库外。机器结果记录选定制品 SHA256、treeDigest、原始日志摘要及未达成项。

原生客户端是源码锁定测试候选：commit `9fb453dc9a6709a07ea6f51ce292dd3e3e93536f`，版本 **0.8.5 为测试构建覆盖值**，没有声称对应公开 release。两份二进制均记录 `vcs.modified=true`，Go 构建输入与该 HEAD 相同，最终工作区差异只有另外的 `docs/servers.md` 修改；因此候选来源状态记录为 worktree。Linux 网关锁定 commit `25d55cf08ab08ec8b8e3701e3cd1b62f8022eae5`，两者代码差异仅文档。原生 zsetup 是 i686 Windows 产物在 AMD64 系统上的有限验证，不代表该核心全部发布门禁通过。

网关 mirror 只允许 localhost 的保护未放宽。初次桥接命中 403 后，改为在容器 SSH 网络命名空间内建立回环连接，再转发给桌面。Windows Node SDK 实收 34,906,389 字节，Go SDK 实收 87,183,196 字节；原校验和、Go sum、npm SRI 保持。一次 npm-exec 探针额外下载了任务缓存内的临时 Node 包；随后以选定 SDK 的直接执行和版本断言作为实际运行依据，不使用该探针推断冻结运行时。

- 本地 `unittest discover`：120 项，118 通过，2 项原生专用检查跳过；原生专用检查另在目标执行 3 次，全部通过。
- 16 个仓库验证脚本通过，覆盖架构、安装、发布、预算及平台契约。
- Reasonix 八层 canonical 快照已同步，来源锁检查通过。
- 现有全局配置检查：macOS 5 项、Windows 9 项均未改变。jq 临时用户 launcher 由原安装器删除。
- 清理后本轮 Docker 容器、网络、镜像均为 0，临时网关与 SSH 转发已停止。数据盘内测试目录保留用于复现，不含真实 Agent 目录安装。

原生专用检查接受 `KAI_NATIVE_PRESET`（解压后的 preset 目录）和 `KAI_NATIVE_WORK`（独立工作目录）；Windows 另设置 `KAI_NATIVE_BASH` 为已验证 Git Bash 的绝对路径。分别运行上述两个 Python 测试文件。它们不包含 SSH 目标配置。

参考：[PowerShell 命令行与退出语义](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1)、[官方 WinGet 模块](https://www.powershellgallery.com/packages/microsoft.winget.client/1.29.380)、[官方 Source 的 best-effort 实现](https://github.com/microsoft/winget-cli/blob/master/src/PowerShell/Microsoft.WinGet.Client.Engine/Extensions/CatalogPackageExtensions.cs)。
