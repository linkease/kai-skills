# MS10 分发与综合验收

状态：通过；初始实现后进行了 3 次优化。MS0–MS10 的规定验收现均已完成。
本结论限于计划声明的 fixture/container 范围；不把未执行的原生桌面范围计为通过。

## 交付

- 六个通用主技能：`kai-software`、`kai-dev-environment`、`kai-project-dependencies`、`kai-download-acceleration`、`kai-storage-files`、`kai-tool-bootstrap`。
- Ubuntu、Debian、iStoreOS、macOS、Windows 各有 on-device / remote-control，共十个声明生成的预设。
- 四个旧主 ID 迁移到唯一通用实现；十六个 iStoreOS 原生技能保留。旧原生脚本作为声明资源保留，安装/升级/卸载均校验所有权和摘要。
- Kai 同步八个 canonical 层及实际来源锁；通用技能只保存一次，不混入第三方 Transport。目标系统与控制端系统分开判断。
- iStoreOS 的 runtime adapter 随包携带并校验所有者源码摘要。已有完整 jq 但缺少 zsetup 时，可独立引导冻结版本 core。
- Windows 首次无 Bash 时，先通过原生 PowerShell 引导实际 Git Bash，再运行 shell 安装器；WSL 视为独立 Linux 目标。

## 最终真实容器结果

| 目标 | 秒 | on-device | remote-control | 全新环境重复 |
| --- | ---: | ---: | ---: | ---: |
| istoreos | 527.468 | 3 | 3 | 3 |
| ubuntu | 701.331 | 3 | 3 | 3 |
| debian | 639.592 | 3 | 3 | 3 |

每种模式的三条旅程分别为：查询/安装并实际使用软件；安装 Python SDK 并运行锁定 pip 依赖项目；分析空间并搜索中文文件。
合计十八条 required、九条全新环境重复。重复环境独立创建容器、HOME、项目、客户端缓存及网关缓存；九个网关实例 ID 不同。

每个最终回执的 source/tree digest 都与同一套候选归档一致。当前 pip 元数据、wheel 原始 SHA、TLS 端口及实际项目执行有同实例/同窗口证据。
MS7 十通道证明另行关联，并核对 `currentCandidates` 的客户端/网关 SHA 和源码提交；不把历史证明冒充本轮新观察。

iStoreOS/Ubuntu 使用优化 2 已通过且归档字节相同的结果；Debian 使用优化 3 的完整结果。优化 3 仅把测试回执变量 `$end` 改为兼容 jq 1.6 的名称。
修改前已在实际 Debian 上复现，修改后三个系统的真实固定密钥 SSH 探针均保留字面参数、中文/空参数、原始退出37及 stderr 摘要。
原始失败与旧包 Ubuntu 结果保留在 `release/ms10-evidence/history/`，未覆盖或混计。

## 其他验收

- 全量离线测试118项通过；规定契约11组通过；既有基线15组通过。
- 临时目录中实际运行 Codex/OpenCode 两类安装布局，共20种组合；实际 Reasonix Skill Store 和路由器验证新 ID、别名、触发词与安装后脚本路径。
- Kai/Reasonix 精确解析旧别名；其他 Agent 根据 `migration.json` 迁移到新 ID。本轮未启动真实 Codex/OpenCode 应用进程，不假定其原生支持项目扩展元数据。
- 基准提交中的旧版20技能预设 → 新版22技能的真实升级、冲突保护、无关文件保留及卸载通过；未触及真实 Agent 目录。
- Kai 相关 skill/capability/systempack/sessioncapability/kaiplusweb、目标选择 CLI 与 Agent 检查通过；canonical source lock / 实际树摘要检查通过。
- 额外扩大到 Boot 的检查中，有6项顶层测试失败（含子用例共8条失败事件）；隔离的原始 HEAD 复现相同失败，成功事件数量也一致，确认无新增失败。该组未被标为绿色，未扩大本次修改去修复既有会话持久化问题。

## 候选制品与保护检查

`release/ms10-candidate/` 保留20个归档及清单，两次构建逐字节一致；所有归档均已解包、校验并实际安装到临时目录。

- 清单 SHA256：`eefa0451303d64fd6051bde8b2ca5a116ad48d087bcac1c18d77a536378f6071`。
- 来源基准：`a7c5b1e7a855edcbac21ed25e46515e540fc4fae`；`sourceState=worktree`，实际内容另有 source/tree digest。未提交候选不是已发布版本。
- 详细结果：[multisystem-ms10-results.json](multisystem-ms10-results.json)；原始规定用例日志及额外基线对照保存在本地 `release/ms10-evidence/`。
- 最后审计：本 run 容器0、网络0；剩余22128656384字节（约20.61GiB）；已迁移的 Docker root 未改动。
- 宿主 curl/libcurl/zstd/jq/opkg/SSL 前后快照一致；三轮 iStoreOS 容器的系统 curl/SSL 保护检查均通过。

未发布公网制品、未生产部署、未连接 Windows。macOS/Windows 原生内核、真实 WinGet/PowerShell5.1/cmd/MSYS/卷 API、未覆盖架构及真实内核/服务行为仍待验证。

## 后续原生桌面验收（2026-10-28）

本文件保留 MS10 当时的历史范围。用户后续已授权连接 macOS/Windows；新增实测、三项修复及仍未达成的桌面门禁见 [原生桌面验收](desktop-native-20261028.md)。本次候选与 MS10 旧候选分开保存，不把旧 Linux 制品证据移用于新桌面制品。

桌面后续三轮专项修复：见 [最新报告](desktop-optimization-20261028.md) 与 [机器结果](desktop-optimization-20261028-results.json)。原 8 项阻塞已关闭 7 项，WinGet 原生目录 API 仍待验收；不改变本页历史范围。

再次授权的遗留修复见 [后续报告](desktop-followup-20261028.md)：jq PS5 入口已修复，
WinGet 空版本失败边界通过，官方 CDN 连接重置仍阻塞成功查询。

最新 [WinGet 加速实测](winget-acceleration-20261028.md) 已通过真实 kspeeder 和官方 SDK
读取目录；原生 CLI 下载/安装的代理开关仍待产品选择，不改写 MS10 历史范围。
