# 2026-11-05 新版 KSpeeder 业务验收批次

用户授权在 skills 开发完成、KSpeeder 更新后继续开发测试。历史 BM7/BM8 的失败和部分成功保留，本批按当前提交与独立包摘要重新验收。每个里程碑失败最多优化三轮；三轮仍失败或需要产品语义决策时暂停。

## 版本与环境基线

任务树：冻结 skills/KSpeeder/子模块 → 检查旧修复是否进入新版 → 只读连接/容量/服务快照 → 冻结程序摘要与测试路径。

验收：输入来源、版本和哈希可追溯；私有连接配置、密钥、指纹和设备状态保留仓库外；未知/变更的 SSH 主机密钥停止连接。远端只在既有授权目录及明确归属容器中测试；复用冻结镜像前核验镜像 ID。首次 KSpeeder 基线为 `8b92b446f09c3d1f706145bf6a46172dcd84566d`，skills 基线为 `491b707bb8af5f66d1e3540602c6fd8230cd4d8b`。

## 依赖修复整合

任务树：重放三项历史回归 → 记录最新代码红灯 → 单独提交测试 → 整合最小修复 → 当前 checkout 正常/race/编译检查。

验收：mise 版本查询只对子进程离线；Git 正式适配提供本地网关解析，保留 Host/SNI/TLS/原 remote；签名失败可用既有下载通道回退，但不绕过原站 403/404/429、不把代理 404 当作原站缺失。无 WinGet CONNECT、默认代理/信任/吊销策略修改。测试与实现分别提交；不能用旧分支绿灯替代本批执行。

## BM7 Linux 业务

任务树：软件源与 Git 前置 → 三系统 18 个独立业务 → 两业务集合乘三系统 → 两模式系统集合及 fresh repeat → 专属能力与保护审计 → 清理。

验收沿用原 BM7：独立目录只出现所选 SKILL.md；原包管理器精确版本安装及实际使用；mise Node、npm、校验下载、固定 Git commit/tree、空间及中文查找通过；iStoreOS 系统 curl/TLS 不改，原软件包校验不放宽；共享归属生命周期与失败边界正确。真实加速证据与普通直连分别记录；旧候选成功不能直接拼为新候选通过。

## BM8 macOS / Windows

任务树：六项独立业务乘两系统 → 开发/软件业务集合 → 两模式系统集合 → Windows 首次入口/mise/签名 → WinGet EXE/MSI/依赖及服务生命周期 → 配置和清理快照。

验收沿用原 BM8：按最终包/程序摘要完成真实业务使用；WinGet 原始元数据、载荷完整性、原生签名与依赖、注册版本和服务结果逐项记录；原生目录网络与 CRL/OCSP 健康独立记载；npm 安装与 audit 分开判断。保留既有软件/服务，临时进程和端口清理。没有执行的用例保持未验证。

## BM9 最终候选

任务树：整理修复与来源 → 冻结干净提交 → 重建 86 归档 → 关联最终内容摘要的原生证据 → 本地回归及 release gate。

验收：生成一致、两次构建相同、离线安装生命周期通过；110 条必需证据（含 30 个独立原生正向用例）与冻结清单匹配。失败/跳过不能当通过；候选未过门禁不能宣布 release-ready。BM10 发布及公网下载复验不由本批代码/本地测试推定完成。

## 实施及自检结果

结果：依赖回归修复、skills 的正式 Homebrew 入口和本地检查通过；BM7/BM8 原生验收仍未通过。Linux、macOS、Windows 分别完成本批最多三轮业务执行，未追加第四轮。结构化结果见 [本批机器记录](business-retest-20261105-results.json)。历史失败保留，各候选分别记录，不能把不同候选的成功拼成最终版本全绿。

依赖整合先在最新 KSpeeder 基线复现历史红灯，再分别提交测试和实现：mise 身份查询局部离线、Git 子进程本地 TLS 域名解析、签名网络/5xx 回退；原始 403/404/429 和代理缺失语义保持。完整 downloadcmd race 检查暴露的旧日志测试竞争已通过同步 handler 完成修复。

原生执行新增三项修复：

- iStoreOS Node 压缩包在代理成功响应但正文不完整时，auto 模式丢弃损坏暂存文件，只额外尝试一次原站完整下载并再次验证 gzip；原生 mise 摘要及签名仍必须通过。新增真实 HTTP 回归先红后绿。第三轮 iStoreOS 开发集合实际命中 `archive integrity recovery selected=origin`，随后 Node 安装及运行成功；集合之后在 Git 包前置失败。
- Homebrew 正式客户端对兼容版本使用私有临时 curl 配置解析本地网关，保留 Host/SNI/TLS、调用方配置及退出清理。显式选择原有 plus artifact alias 时，也解析该 alias；默认仍为 API 路由。`kai-software` 的 `KAI_SOFTWARE_ACCELERATION=required` 执行 doctor 后调用正式客户端，缺失或不就绪时失败；不自动安装服务。真实 curl 测试先红后绿。
- Windows 下载的源摘要匹配 `.mszyml` 是 MSZIP，旧实现误作普通 YAML。增加 Windows 原生 cabinet.dll 有界解压，再共用 schema/条目检查；签名源对线上压缩字节的 SHA256 校验保持。Windows 原生离线测试先红后绿，四项全部通过，包含本批真实源文件。完整 WinGet 安装没有因解析修复而自动计为通过。

### BM7 三轮结果

第一轮：Ubuntu、Debian 独立业务各 6/6；iStoreOS 2/6 后遇到 Node 代理正文截断。第二轮：Ubuntu、iStoreOS 各 6/6；Debian 在文件下载通道及原站超时后停止，4/6。第三轮：三个系统独立业务全部 18/18；iStoreOS 16 项专属入口通过，9 项生产行为仍未验证；开发集合 Ubuntu/Debian 通过，iStoreOS 在 `opkg --noaction install git-http` 的包大小/摘要校验失败处停止。软件管理集合、系统集合及 fresh repeat 本批未执行。

索引前置的原生诊断：同一冻结镜像中，刷新前 Git 安装预演退出 255；`opkg update` 后预演退出 0，curl/TLS 校验及清理通过。独立业务会先执行软件查询/索引刷新，开发集合没有该步骤；已在测试工具缺 Git 的路径补上刷新，再执行现有预演及受保护包检查。本对照支持缺少刷新前置的定位，但不保证镜像源未来始终一致；没有关闭包校验，也没有把预演通过写成整个集合通过。完整集合留待下一批。

### BM8 三轮结果

Windows：第一轮在 Bash 网关健康探测超时，0/6；原生 HTTP 健康成功，改为先确认精确提交再有界探测 Bash。第二轮 4/6，暴露隔离环境仍使用旧 Python shim、缺少 WinGet 原生模块的测试准备问题。第三轮在任务目录保存官方模块、绑定真实已有 Python，5/6 通过：引导、Node 安装与运行、npm 固定依赖安装/导入及锁保持、空间和中文查找、校验文件与固定 Git commit/tree。一次 PowerShell 模块路径准备错误在尚无用例通过前纠正，同轮继续，原错误保留。WinGet 目录可查询 PuTTY 0.85.0.0，实际安装停在压缩元数据解析；此后仅做上述原生离线解析验证，没有第四轮安装。

macOS：三轮均 4/6，引导、Node、npm、空间及中文查找通过。校验文件下载通过，Git upload-pack POST 持续 HTTP 405；只读诊断中目标可达的公共加速入口同样返回 405，原站 POST 超时，不能据此宣称所有上游都不支持 Git。第二/三轮正式 Homebrew 查询成功，签名 API 经本地网关返回 200；实际 bottle 安装未通过。第三轮明确选择 artifact alias 后，本地网关收到 manifest/blob 请求并返回 403，正文摘要与现有 Plus 权限拒绝响应一致；候选网关未登录，不能绕过或借用既有服务凭据。Homebrew 随后回退原站 `ghcr.io`，最终 DNS 失败。权限前置与最终 DNS 错误分别保留。

桌面业务集合及系统集合、Windows 签名 EXE/MSI、依赖和 SCM start/stop/restart、fresh CRL/OCSP 场景均未验收。运行的 Windows 服务是任务目录前台进程；没有更新用户既有 SCM 服务。

### 本地自检、来源和清理

业务测试 53 项、独立包隔离行为 81 项、桌面契约 25 项、仓库基线 15 组全部通过，无跳过。KSpeeder 完整 CLI app、downloadcmd 普通/race、相关 CLI race 及 Windows vet 通过；构建 Linux amd64、macOS arm64、Windows amd64 六个候选程序。生成一致性与 whitespace 检查通过。测试工具新增索引前置的依据为上述真实预演对照；没有把它计作新一轮完整集合验收。

最终程序源码提交为 `f5665424f3af5ce3bd8f1bc07598da2103656154`，只在 macOS 第三轮使用其完整程序；Windows 第三轮使用 `3eee9f61`，Linux 第三轮使用 `b690c4d3`。最终 Windows 解析测试覆盖后续源码，但不代表最新完整程序已完成 WinGet 安装。构建使用固定子模块、从模板生成的版本文件和本地已有嵌入资源，相关文件摘要留档；这是记录清楚的验证构建，不是已发布制品。macOS 原 harness 的 gatewayProgram.sourceCommit 残留旧常量，校正后的来源以实际二进制摘要匹配构建清单、运行时 capabilities 为准，原回执不篡改。

Linux 本批及诊断容器/网络均已清理，Docker 所在文件系统仍约 22 GB 可用，无需迁移或清除其他数据。iStoreOS 系统 curl、库及 TLS 配置保持；macOS 临时监听和程序清理，测试前未安装的 tree 仍未安装；Windows 临时端口/程序清理，既有服务的状态、启动模式和路径与本批前相同。本批未记录既有服务二进制的前置 SHA256，不能宣称完成这一项哈希比对。SDK、缓存和日志只保留在归属明确的任务目录，私有连接配置和原始日志在仓库外。

BM9 保持 awaiting-native-acceptance，release-ready=false；BM10 未发布。下一批需要明确重新授权三轮原生验收，并先准备 GHCR 允许的测试会话、定位 Git 405 上游方法支持，再按最终候选验证 Linux 集合与 WinGet 安装/依赖/服务；账户权限和服务变更不得由本轮成功的本地测试推定获得。
