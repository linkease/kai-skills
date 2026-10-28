# 桌面状态确认与 Windows mise 引导修复

结论：**macOS arm64 本轮功能范围已验收完成；Windows mise 引导组件通过，桌面完整发布门禁仍未达成。**
用户要求暂缓此前 WinGet 在线 CRL/OCSP 问题，本轮没有继续修改网络或证书策略。
逐项状态、原生日志摘要与候选摘要见[机器结果](windows-tools-20261028-results.json)。

## macOS 的完成范围

[专项验收](desktop-optimization-20261028.md)已通过固定版本 Python、Node、Go、uv
安装和 pip/npm/Go/uv 实际项目，也通过既有 Homebrew Python 原前缀复用。
[后续验收](desktop-followup-20261028.md)确认最终 preset 的原生安装、升级、卸载及
APFS 检查通过。此前发现的 macOS 功能问题已关闭，本轮没有重复安装这些 SDK。

这个结论限于原生 arm64 和报告列明的用例。其他架构、桌面 Docker、真实 Agent
应用，以及尚未发布的桌面内部客户端一键安装，不属于已完成范围。

## Windows 的问题与任务树

此前 SDK 与依赖项目测试复用了预置 mise 2026.7.0。虽然锁文件已经登记官方
Windows x64 mise ZIP，公开 `tool.sh plan mise` 在没有 mise 时仍返回 unavailable。
因此“开发任务可以运行”和“缺少 mise 时能引导”必须分开验收。

| 任务 | 可测试的验收标准 | 结果 |
| --- | --- | --- |
| 复现与计划 | 公开 plan 返回明确安装命令；不创建工具或 staging 目录 | 先红后绿 |
| 安装与归属 | 固定版本、原 SHA256/大小；两份原生 exe；PS5 安装、PS7 复用；保护外部文件 | 通过受校验的原始归档缓存路径 |
| 公开使用与交付 | Git Bash ensure 安装/复用；改动 companion 后返回冲突；最终制品、consumer、生命周期及配置保持 | 通过 |

## 最多三轮优化

初始原生测试发现 PS5 在参数默认值中不能取得脚本目录，尚未进入安装。

| 轮次 | 修复与自检 |
| --- | --- |
| 1 | 将默认锁路径解析移入脚本主体；保护测试通过，随后实际调用发现发布的 zsetup 0.4.0 不支持新增的 max-bytes/min-free-bytes 参数 |
| 2 | 使用该核心已支持的下载参数和原生磁盘空间检查；保留 SHA/大小、超时及有界 ZIP 提取。原始归档缓存下 4 项通过；直连上游 TLS 失败。补充改动 companion 回归后，复现外层复用只检查主程序的问题 |
| 3 | 公开 discovery 在执行主程序前核验完整受管安装；canonical stage 和最终 preset 的 4 项原生测试通过，preset 生命周期通过 |

没有第四轮产品优化。检查启动器遗漏 Reasonix 源码目录参数的一次调用未执行产品
代码；补齐参数后原检查通过，保留最初失败记录。

## 实现与调用

canonical `install-mise.sh` 调用原生 `install-mise-windows.ps1`，复用既有 zsetup。
核心缺失时仍走原始、校验过的 Windows core bootstrap。该分支不依赖 WinGet。
Windows x64 当前固定为 mise 2026.8.14，同时安装 `mise.exe` 和 `mise-shim.exe`。

只提取锁定归档内的两个明确条目，校验归档 SHA256、大小、PE 标记和实际版本；
保留归属 receipt，重复调用核验两份文件。外部文件、改动文件及 reparse 路径返回
冲突；不覆盖原工具，不修改持久 PATH、mise 配置或 Windows 默认代理。

```bash
bash scripts/tool.sh plan mise
bash scripts/tool.sh ensure mise
```

目标直连官方 GitHub 下载本轮返回原生 zsetup exit 14，日志明确为安全连接失败。
**未宣称直连冷下载通过。** 通过可信 Transport 预置原始 ZIP 后，可在目标任务内
设置 `KAI_MISE_ARCHIVE_CACHE` 为其路径；同一个公开 ensure 入口仍要求锁定 SHA256
和大小，并由原生 zsetup 验证。原生完整安装与实际 `--version` 已通过这条路径。
缓存来源是官方原包，不是替代可执行文件或绕过校验。

## 交付与验证

- 本地 139 项：124 通过，15 项原生专用跳过；本轮原生另执行 mise 4 项与
  preset 生命周期 1 项，最终均通过。此前 PKI 原生测试没有重新执行。
- 16 个仓库检查通过；10 个 preset 重新生成，8 层 consumer 同步并核验。
- 最终 Windows 归档在原生目标解压，21 个 bootstrap 文件与 canonical SHA 相同；
  实际安装、升级、卸载及公开 mise ensure 再次通过。
- macOS 5 项、Windows 9 项原配置保持；两机本任务进程为 0。
  Windows 默认代理仍关闭，20 项注册表值摘要与此前基线相同。
- 删除两个明确归属的探针目录；保留原始 ZIP fixture 和复现数据。
  本轮没有创建 Docker、网关或转发，没有触及 iStoreOS curl/库或生产服务。

候选目录 `release/windows-tools-20261028-candidate`，20 个归档，sourceState 为
worktree，未发布。manifest SHA256：
`15e782cae0f4da4ef726c461b15e0db83f8005f85addafe2d803d6d536f68b65`。

## 保留项

1. [WinGet 下载的在线撤销查询](windows-pki-implementation-20261028.md)：用户暂缓，未解决。
2. 本轮原生 zsetup 直连官方 mise URL 的 TLS 失败：保留失败证据；原包缓存安装已通过。
3. 桌面内部客户端正式制品、一键交付、其他架构及未测桌面能力：不能用测试候选替代发布验收。

MS0–MS10 历史记录保持，完整桌面发布结论继续为 partial。
