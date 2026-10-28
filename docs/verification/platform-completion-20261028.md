# 多系统完成情况（2026-10-28）

MS0–MS10 已按各里程碑声明的范围通过。后续 macOS、Windows 原生测试已有独立证据，
不能将历史容器、离线契约或某一架构通过推广为所有平台、架构及正式发布通过。

| 系统 | 已完成及实际验证的范围 | 结论与边界 |
| --- | --- | --- |
| Ubuntu | 真实容器中的软件查询、安装及使用；mise 开发环境和项目依赖；下载加速、空间/文件操作；两种执行模式及安装生命周期 | MS0–MS10 声明范围通过；容器证据不覆盖实体机内核、全部架构或所有软件 |
| Debian | 同上；Debian/jq 1.6 回执兼容及真实 SSH 参数、退出状态验证 | MS0–MS10 声明范围通过；容器证据具有相同边界 |
| iStoreOS | 同上，另有原生系统技能、完整受管 jq、iStore runtime adapter 和旧技能 ID 迁移 | 声明容器范围通过；保留系统自身 curl、库、opkg 和 TLS 策略，未替换系统 curl |
| macOS arm64 | 原生 Python、Node、Go、uv 安装；pip/npm/Go/uv 项目安装并运行；Homebrew Python 复用；APFS 文件/空间操作及预设安装、升级、卸载 | 原生已测功能范围通过；不代表其他架构、桌面 Docker 或正式发布完成 |
| Windows AMD64 | PowerShell 5.1/7、Git Bash、jq、文件/空间及执行生命周期；历史四类 SDK/项目使用通过；最新公开入口通过 ks-cli 自动选路下载 mise，再安装并运行 Node/npm 项目 | 已测核心链路通过；WinGet 下载/安装暂缓，npm 审计 POST 返回 405；完整桌面发布门禁仍未通过 |

最新 Windows 专项中，mise 下载未使用预置归档缓存，实际由 ks-cli 的 auto 策略选择
网关通道；Node SDK、npm 元数据/包和通用文件下载均有同实例、同窗口加速证据。
保留原 SHA、size、npm SRI 和 TLS 验证。Windows 未安装或启动本地 KSpeeder 服务，
使用的是隔离控制端网关；未更改 Windows 默认代理。新引导的 mise 本轮仅重新验证了
Node/npm；Python、Go、uv 的原生成功来自此前测试，不计为本轮重新安装通过。

仍保留以下事项：

- **WinGet**：用户决定暂缓在线证书吊销查询导致的下载/安装失败；目录查询的成功
  不能替代下载/安装验收。允许显式命令代理，不改变系统默认代理。
- **npm audit**：已测网关的两个审计 POST 接口返回 HTTP 405。包下载、SRI、
  `npm ci` 和实际使用已通过，安全审计未通过，没有关闭审计来宣称成功。
- **发布及覆盖**：本地候选尚未正式发布；内部客户端桌面一键制品、其他桌面架构、
  桌面 Docker 和真实 Agent 应用进程仍需独立验收。

最近一轮本地测试发现 144 项，127 项通过、17 项原生专用测试跳过；另有 6 项
Windows 原生 bootstrap 用例、最终 Windows 预设生命周期、4 组加速证据通过。
16 组仓库检查、10 个生成预设及 8 个 Kai canonical 消费层校验通过。
MS10 额外 Boot 检查曾发现并在原始 HEAD 复现既有失败，该组没有计为通过。
这些数字分别属于各报告的测试范围，不累加为跨系统统一覆盖率。

证据入口：

- [里程碑状态及最新桌面状态](multisystem-status.json)
- [MS10 综合容器验收](multisystem-ms10.md)
- [macOS/Windows 四类 SDK 与项目原生实测](desktop-optimization-20261028.md)
- [Windows 最新 mise、Node/npm 加速与使用](windows-mise-acceleration-20261028.md)
- [WinGet 暂缓事项的诊断及修复边界](windows-pki-implementation-20261028.md)

设备绑定、凭证、私有路径及原始运行日志保存在仓库外；历史报告保留其当时来源、
候选摘要及结论，本次提交不将旧候选改写为新提交的重新实测结果。
