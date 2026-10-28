# 桌面专项修复：问题、方案与三轮验收

后续授权的遗留问题修复见 [后续报告](desktop-followup-20261028.md)。本页保留当时事实。

这是 `desktop-native-20261028.md` 之后的新一轮授权，历史 partial 结论保留。
目标设备配置、信任文件、原始日志和进程状态只保存在仓库外。

最终结论：**partial，三轮已结束**。原有 8 个阻塞关闭 7 个；28 项本轮原生检查
通过，WinGet 原生目录 API 仍不可用。另记录一项不属于 Kai Bash 主链路的
独立 owner PowerShell 5.1 包装问题。全部逐项证据摘要见
[机器结果](desktop-optimization-20261028-results.json)。没有发布客户端或升级生产网关。

## 初始诊断清单

| 门禁 | 已复现的事实与定位 | 修复边界 |
| --- | --- | --- |
| macOS 冻结 SDK 首装 | 系统 getaddrinfo 对普通上游及 dl-* 网关域名均失败；dig 上游也超时 | 修复命令内的网关回环连接；不修改系统 DNS/hosts |
| macOS Homebrew Python 复用 | framework prefix 缺 unversioned python，mise exec python 失败 | 不创建伪造 SDK；独立 SDK 首装与外部布局复用分开验收 |
| macOS pip/uv 在线使用 | 前置 Python/网络未通过 | 前置修复后运行原项目和完整校验 |
| Windows Python 首装 | 归档下载完成，api.github.com attestation 请求失败 | 在 owner 补充证明 API 路由，保留原证明验证 |
| Windows pip | 全局 Python、venv Python、pip --version 均快速完成；完整入口在 pip install 卡住，无索引对照也超时 | 继续最小化，不能直接归因于网络或 mise exec |
| Windows uv | 原生日志请求 /data/uv.toml 和 GitHub releases API；现有规则仅覆盖 /tools/ 和 release archive | 补齐实际元数据路径与 capability 协商 |
| Windows WinGet | PS5/PS7 都有 ID、空 Source/AvailableVersions；原生 show 报 source update 失败后超时 | 保留来源检查，区分不可用 catalog 与包不存在；不凭空填充来源 |
| Windows 缺 jq/核心 | POSIX bootstrap 只支持 Linux/Darwin；原生 Windows bootstrap 已有 canonical owner | 同步原始 PowerShell bootstrap，校验来源，再调用原 jq owner |
| 新增：超时残留 | 查询到本任务 bash/mise/env/python 后代；断开 SSH 不保证后代退出 | Transport 增加原生有界执行/后代回收，单独回归 |

## 统一任务树

1. 第一轮：入口与失败边界
   - 补 Windows 原生核心引导；覆盖缺 jq/核心路径。
   - WinGet 对完整、缺失、冲突和不完整 catalog 分别返回正确结果。
   - 最小化 pip 卡顿，补有界执行和任务进程回收。
   - 验收：公开入口回归先红后绿；失败无成功声明；无任务进程残留。
2. 第二轮：加速链路
   - 在 ks-cli/网关 owner 补 mise 元数据、GitHub releases/attestation 路由。
   - capability 不满足时在目标程序启动前失败；命令内 TLS 回环连接不依赖系统 DNS。
   - 真实安装固定 Python 3.13.7、Node 22.14.0、Go 1.24.1、uv 0.8.22。
   - 验收：原 TLS、checksum、SRI、go.sum、attestation 保持；四类项目安装并运行。
3. 第三轮：交付复测
   - 生成全平台 preset，同步 Kai canonical 层及来源锁。
   - 新目录进行 macOS/Windows 原生复测及 Linux 契约回归。
   - 验收：制品摘要、逐项状态、配置保持与资源清理都有证据。

每轮只修复已定位的问题。最多三轮，仍失败保留阻塞结论。连接故障、fixture
通过、归档下载完成均不能替代原生完整安装成功。未授权生产发布或系统网络修改。

## 三轮执行与自检

| 轮次 | 实施与定位 | 自检结果 |
| --- | --- | --- |
| 1：入口、错误与回收 | WinGet 不完整 catalog 区分于包不存在；Windows Job 在放行子进程前完成归属，超时/关闭时回收后代；同步原始 Windows core bootstrap | WinGet 回归先红后绿；真实 param/中文/退出 37 与超时后代检查通过。jq 首次验证发现通用工具检查反过来依赖 jq |
| 2：执行与完整加速链 | jq 无 jq 阶段直接检查已验证核心的版本；定位 pip User-Agent 的 rustc 探测；仅在显式隔离的 Windows mise 数据根中排除继承的其他 mise shims；选用 SDK 内真实版本化 Python 入口；owner 增加 /data/、GitHub release/attestation 与 Sigstore TUF 路由及 capability | pip 的同一完整入口由超时变为约 7.6 秒成功；Homebrew Python 3.14.6 原前缀复用通过。URL authority 占位符缺陷由真实子进程回归捕获并修正。jq 后续失败为真实下载网络超时 |
| 3：新制品、在线链与收尾 | 新目录 stage 最终 preset；mise observer 对已知网关保留 Host/SNI、连接回环；包管理器使用命令范围 CONNECT relay，保留已有代理优先级；冷项目和冻结 SDK 原生复测 | 两平台 4 个固定 SDK 和 pip/npm/Go/uv 项目全部通过。Windows 新目录缺 jq/核心引导通过。macOS uv 首次 300 秒预算不足，保留缓存后以 180 秒请求期限/600 秒总预算重试，约 404 秒完成原安装与验证。没有关闭校验或换 backend |

pip 的实际堆栈停在 `user_agent → check_output(rustc --version, timeout=0.5)
→ communicate → readerthread.join`。继承的另一套 mise `rustc.EXE` shim
会留下输出管道，解释了无索引安装同样挂起。修复不删除 shim、不修改全局 PATH；
普通编译器目录和所选 SDK 保留。回归直接观察公开依赖入口是否探测未选择的 shim。

Homebrew Python 修复使用 framework 内的 `python3`/版本化真实入口，继续验证
可执行文件归属和准确版本。venv 创建也使用这一选定解释器，不伪造 SDK 目录。

## 本轮最终矩阵

| 能力 | macOS arm64 | Windows AMD64 |
| --- | --- | --- |
| Python 3.13.7 / Node 22.14.0 / Go 1.24.1 首次安装 | 全部通过 | 全部通过 |
| uv 0.8.22 安装、来源和版本 | 重试后通过 | 通过 |
| pip + idna 3.10、项目 venv、实际导入 | 通过 | 通过 |
| npm ci + is-number 7.0.0、实际版本及函数 | 通过 | 通过 |
| Go uuid 1.6.0、go.sum、实际程序 | 通过 | 通过 |
| uv + idna 3.10、新 venv/cache、实际导入 | 通过 | 通过 |
| 既有 Homebrew Python 3.14.6 原前缀复用 | 通过，区别于冻结 SDK 首装 | 不适用 |
| 缺 jq 与核心的公开 jq ensure | 复用原系统 jq；未宣称 macOS 核心首装 | 新 rescue 目录引导通过；官方 Windows i686 核心在 AMD64 上的有限验证 |
| 最终 preset 原生安装/升级/卸载 | 通过 | 通过 |
| APFS 原生回归 / Windows 超时后代回收 | 通过 APFS 回归 | 通过退出状态与后代回收 |
| WinGet 真实 structured info | 不适用 | 未通过，保留阻塞 |

Windows npm 的第一次验收脚本误调用了 fixture 中不存在的 `check` script：安装
receipt 已通过，但整个脚本返回 1。随后用选定 Node 独立检查实际 package version
和函数，确认 7.0.0；没有通过修改生产实现掩盖验收脚本错误。

下载保持 TLS、原 SHA/size、npm SRI、go.sum 和 Python attestation。CONNECT relay
只转接加密流量，由原生包管理器校验证书；不信任证书拒绝、原代理优先和退出后
监听关闭均有实际进程回归及 race 检查。Windows npm/pip 仍按已验证的公开 Explain
计划使用所选 SDK 的原生入口；uv/Go 和 macOS 包管理器通过客户端执行。

## 保留的阻塞与补充发现

**WinGet 不是已修复成功。** 三轮中，官方签名模块在 PS5/PS7 都出现空
Source/版本信息，后续两个不同软件 ID 查询超时。显式 `software.sh refresh winget`
返回成功，但再次查询返回 `source-mismatch`，原生版本属性读取仍会阻塞；不使用
新监督器的直接原生调用也卡在模块导入后的 Find。问题已定位到原生目录 API/数据
读取层，更深的 COM 兼容性或源数据根因尚未确证。保留来源检查；未安装或卸载
系统包，也没有解析人类输出冒充结构化结果。按本轮上限停止继续优化该路径。

回收临时 jq 时，额外复现了未改动的 owner `jq-install.ps1` 在 PowerShell 5.1
中对 Bash `-c` 的原生参数引用错误。使用同一 owner 的 Bash 公开入口完成了删除，
确认临时用户 jq 命令消失；PowerShell 7 的 `--help` 能到达原始入口，但未声称其
完整生命周期通过。该独立 PS5 便捷入口不属于已通过的 Kai Bash 主链路；owner
资源保持原字节及来源锁，后续应在 owner 维护源中修复，而非手改生成资源。

`jq.sh ensure` 的内部核心引导不会给调用者父 shell 导出变量。后续独立使用该
核心时，可以调用 `bootstrap-core-windows.ps1` 获取经 owner 验证的路径，再显式
传入 `KAI_ZSETUP_BIN`。这不代表全局 zsetup 命令已注册。

## 制品、验证与清理

最终候选目录为 `release/desktop-opt-20261028-candidate`，20 个制品，sourceState
为 **worktree**。manifest SHA256 为
`4676eaf1bec9738780585ac4a2b3cfc894dc04ca6df0e3028d65f1c337e09876`。
选定 tar、treeDigest、每项原始日志摘要和各客户端二进制 SHA 均记录在机器结果。

网关与首批 SDK 客户端来自 KSpeeder commit `97b7d2b`，增加 package relay 的客户端
来自 `a3c31cd`。客户端 `0.8.5` 是测试构建覆盖值，不是公开 release。五个二进制的
摘要及嵌入 Go 来源信息已核验；`vcs.modified=true` 对应 owner 原有的另一个文档
修改，测试 Go 输入与所记 commit 一致。不能将手动放置的测试客户端当作桌面
ks-cli 一键安装器已发布的证据。

- 本地 124 项：122 通过，2 项原生专用检查跳过；原生专用检查另执行 3 次，全部通过。
- 16 个仓库验证脚本通过；8 层 Kai canonical 快照和 owner 来源锁检查通过。
- ks-cli 全 app 测试、relay race/TLS/代理优先/关闭检查通过；网关 downloadcmd、
  domainfold、multi 三包最终验证通过。首次包级并发测试有一项 3 秒刷新时限失败，
  单项和最终 `-p 1` 三包复跑通过，未为此修改生产代码。
- macOS 5 项、Windows 9 项原配置检查均保持；WinGet 只执行了明确的源 metadata 刷新。
- 临时用户 jq 由原 Bash owner 删除；两台设备没有本任务残留进程。
- 本轮 Docker 容器、网络、镜像和活动转发进程均为 0；原始日志已保存在仓库外。
  数据盘测试目录保留用于复现。

未验收其他桌面架构、桌面 Docker daemon、真实 Agent 应用运行、系统包安装/卸载
及服务变更；原 MS0–MS10 历史范围和首次原生记录保留，不冒充本轮证据。

本地复查先按[桌面执行契约](../architecture/desktop-execution-contract.md)设置
`KAI_DESKTOP_PWSH` / `KAI_DESKTOP_BASH32` 为已验证工具的绝对路径，然后执行：

```sh
# kai-skills
python3 -m unittest discover -s tests/multisystem -p 'test_*.py'
sh tools/verify-generated.sh
python3 tools/sync-kai-system-packs.py

# kspeeder/kspeeder-cli
/var/cache/build-cache/run.sh -- go test ./internal/app -count=1
/var/cache/build-cache/run.sh -- go test -race ./internal/app -run TestPackageProcessReachesLocalGatewayWithoutDNSAndVerifiesTLS -count=1

# kspeeder/kspeeder
/var/cache/build-cache/run.sh -- go test -p 1 ./downloadcmd ./domainfold ./cmd/multi -count=1
```

原生专用检查继续使用 `KAI_NATIVE_PRESET`、`KAI_NATIVE_WORK` 和 Windows 上的
`KAI_NATIVE_BASH`，运行 `tests/multisystem/test_native_desktop_lifecycle.py`；macOS
另运行 `test_native_macos_storage.py`。它们只操作指定的测试目录，不包含 SSH 绑定。
