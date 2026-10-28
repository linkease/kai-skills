# WinGet 经 kspeeder / ks-cli 加速

后续用户已授权并完成显式代理开关启用，原生查询及下载的实际结果见
[原生 CLI 验收](winget-cli-20261028.md)。本页保留启用之前的事实。

结论：**官方目录查询加速已通过；原生 CLI 下载/安装等待产品选择**。
真实 Windows 的公开软件入口通过 ks-cli 和真实 kspeeder CONNECT 代理，读取了
原注册 `winget` 官方源的版本及已安装状态。没有替换系统源、解析显示表格或伪填来源。
逐项结果与摘要见 [机器证据](winget-acceleration-20261028-results.json)。

## 任务树和验收

1. 验证接入点：对比 CLI 显式代理、模块执行模式和官方 SDK。
   验收：真实版本、实际 catalog 来源及中继请求有证据；不修改 Windows 默认代理。
2. 实现 owner 能力：复用 kspeeder 已有的认证 CONNECT，实现 ks-cli 命令范围中继。
   验收：公开 CLI 测试先红后绿；认证前不启动子程序；TLS/参数/退出码及关闭通过。
3. 接入 Kai 和交付：锁定 SDK、生成 preset、同步 consumer、目标原生复测。
   验收：完整依赖准备、实际查询、错误回执、制品摘要和配置保持检查通过。

## 三轮实施

| 轮次 | 实施和定位 | 自检 |
| --- | --- | --- |
| 1 | 确认控制侧能读取相同官方 CDN；验证官方 SDK 的进程内接口及 WinINet 非空句柄的进程范围代理；复用原有 kspeeder CONNECT，而非新增下载网关 | 临时中继下实际读到 PowerShell 112 个版本；owner 公开 CLI 回归由 UNKNOWN_COMMAND 转为通过；SDK 直接准备在 Gallery TLS 处失败 |
| 2 | ks-cli 前置认证探测、临时监听及隧道回收；Kai 显式 required 分支、官方 SDK 文件锁、原源和版本 provenance 验证；补 SDK 显式包缓存 | 真实 kspeeder 下 Git.Git 查询通过；PS5 从固定原包缓存调用 zsetup 校验后准备 SDK 通过，约 6.6 秒；新准备的 SDK 执行同一公开查询通过 |
| 3 | 认证失败时补齐 Kai JSON 回执，保留原 exit/stderr；最终归档和 consumer 同步、原生及本地回归、配置/资源核对 | 最终公开原生测试 2 项通过，包括错误认证；macOS/Windows 生命周期、APFS、PS5/PS7 jq 回归通过；127 项发现，123 通过、4 原生专用跳过，原生另执行；16 个仓库检查通过 |

初次认证回执回归使用的 Transport 总预算小于测试自身子进程预算，出现一次
Transport 超时；该结果保留。旧入口另有真实错误认证返回非零但 stdout 为空的
证据。最终同一公开测试在完整预算下通过，不将超时计为成功。

## 实际原生结果

| 操作 | 结果 | 实际内容或错误 |
| --- | --- | --- |
| Git.Git 公开 info | 通过 | 非空版本、真实来源及 acceleration receipt；最终归档的原生测试通过 |
| Microsoft.PowerShell info | 通过 | 可用 7.6.9.0、已安装 7.6.3.0；2 个数据隧道、23823 下载字节 |
| 7zip.7zip info | 通过 | 可用 26.05、已安装 19.00；2 个数据隧道、24708 下载字节 |
| search PowerShell | 通过 | 3 个实际候选；2 个数据隧道、38770 下载字节 |
| 不存在的精确 ID | 通过错误验收 | exit 4 / no-unique-candidate |
| 错误代理认证 | 通过错误验收 | 子程序启动前拒绝；最终 Kai 回执为 acceleration-unavailable |
| accelerated install | 明确未支持 | exit 18 / unsupported-accelerated-operation；未安装或卸载系统软件 |

完整窗口中部分查询约 31–35 秒，最终公开测试组约 41 秒；不声称固定带宽收益。
隧道字节是原生 TLS 数据，CONNECT 不终止原站 TLS，也不提供明文内容缓存。
SDK 内部可能复用目录缓存；ks-cli 始终先验证代理，即使业务数据命中缓存。

当前加速路径为：

```text
Kai Bash 入口 → ks-cli winget exec → 临时 loopback CONNECT
   → 可信隧道内的 kspeeder 认证 CONNECT → 官方 CDN
   → 官方进程内 WinGet SDK 的结构化结果
```

kspeeder 的 CONNECT 已在原实现中存在。测试只启动隔离实例并通过既有可信 SSH
通道访问；没有升级生产网关。实际 SDK 源 URL、包版本 catalog 和精确 ID 均校验。
原站证书、源签名及原生内容检查保持。进程代理使用
[微软规定的非空 InternetOpen 句柄方式](https://learn.microsoft.com/en-us/windows/win32/wininet/option-flags)，
没有调用 NULL 句柄修改系统代理。

## 可使用的入口和依赖

ks-cli owner commit：`32cbbaa8aa0f3fce35b32c3d9497236e136678f5`。
新增 `ks-cli winget exec -- PROGRAM ARGS...`，支持只读 Explain、前置代理验证、
字面参数、真实退出码和 stderr 传输统计。错误认证、源 TLS 不受信任、退出 37
及监听关闭均通过公开 CLI 进程回归和 race 检查。

Kai 使用 `KAI_WINGET_ACCELERATION=required`、`KAI_KSCLI_BIN`、
`KAI_WINGET_SDK_DIR` 和私下配置的 `KSPEEDER_WINGET_PROXY`。
native worker 需要 PowerShell 7.5+ / 当前 X64 SDK 锁；其他架构不宣称已支持。
准备与调用说明见生成 preset 的 `kai-software/resources/winget-acceleration.md`。

SDK 准备复用 native zsetup >=0.4.0，锁定 3 个官方原包和 5 个库文件（约 35.8 MB），
不注册系统模块、不安装 .NET SDK。当前设备直接获取 Gallery 包返回 TLS 错误；
本轮用可信 Transport 预置相同原包，再由目标 zsetup 逐包 SHA/size 校验和有界解包。
这证明缓存准备路径，不证明原生冷下载已经修复。所有库均未嵌入 skills 归档。

## 原生命令的待决选择

本机 WinGet 的 `adminSettings.ProxyCommandLineOptions` 为 false，显式 `--proxy`
被原生命令拒绝。新客户端保留这一错误，未自动开启开关。
`ks-cli winget NATIVE_ARGS` 已实现显式代理转发，但本机完整下载/安装尚未通过。

待选择的具体动作是：

```powershell
winget settings --enable ProxyCommandLineOptions
```

它允许 WinGet 自身接收显式代理参数，区别于 Windows 默认代理设置。用户选择
启用后，继续验证 `ks-cli winget show/download`、原包摘要及必要的安装范围；当前
没有执行该动作。客户端始终不自动改变这一开关。

另一次独立 SDK 安装包下载探索停在官方 SDK 的 `SetUserSettings` 返回 false，
没有开始下载；没有跳过失败或将其列为下载安装成功。当前 Kai required 分支只
开放 search/info。底层 SDK 能查询不代表所有下载器自动遵循同一代理。

## 制品、保护与清理

最终候选：`release/winget-accel-20261028-verified-candidate`，10 个 preset / 20 个归档，
sourceState 为 worktree。清单和选定归档摘要见机器结果。Windows 客户端为测试
构建 `0.8.5-winget-candidate`，不是已发布版本；其嵌入来源与实际 SHA 已核验。

8 个 consumer canonical 层、生成一致性、owner 来源锁和 diff 检查通过。
Windows 20 项代理注册表值前后摘要一致，系统代理保持关闭；macOS 5 项、Windows
9 项原配置保持；两机任务进程为 0。隔离 Docker 容器、网络、镜像和活动转发均清除，
设备数据盘测试资料保留。原始日志、任务认证材料和绑定配置保存在仓库外。
没有公开发布，没有修改 iStoreOS 的 curl、系统 DNS/hosts 或生产服务。
