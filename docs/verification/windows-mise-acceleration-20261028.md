# Windows mise 经 ks-cli 自动选路的实施验收

结论：**本轮下载与实际使用目标通过**。Windows 原生公开入口已通过 ks-cli
获取 mise 原包，安装后再经 ks-cli 安装并运行 Node；npm 查询、安装和实际项目也
通过。完整桌面发布仍为 partial，不能将这些结果扩大为所有平台、SDK 或命令通过。
逐项状态、候选及日志摘要见[机器结果](windows-mise-acceleration-20261028-results.json)。

## 目标、任务树与验收

| 任务 | 可测试的完成标准 | 结果 |
| --- | --- | --- |
| 调整 skills | 文件下载默认使用原生 auto；保留实际选择与探测字节；不强制网关、不启动服务 | 通过 |
| 接入 mise 引导 | Windows 已有 ks-cli 时在线获取官方原包；不用 ArchiveCache 替代；锁定大小/SHA、版本和两个 exe | 通过 |
| 实际使用与交付 | 新 mise 安装并运行固定 SDK；npm 查询/安装/运行；同窗网关证据；最终制品、consumer、配置保持与清理 | 通过 |

这次修复接续[此前的引导验收](windows-tools-20261028.md)。此前的 zsetup 直连
TLS 失败保留；该失败不能替代 ks-cli 选路后的实际结果，也不再用预置 ZIP
冒充在线下载验收。

## Skills 和脚本如何调用

`kai-tool-bootstrap` 在 Windows x64 发现已有 ks-cli 后，使用其原生
`download --mode=auto --allow-start=false` 获取 mise ZIP。`KAI_KSCLI_BIN` 可选择
已有可信原生客户端；`KAI_DOWNLOAD_MODE` 默认 auto，也支持显式 direct、accelerated、race。
下载后仍检查锁定 SHA256、大小，并让原生 zsetup 验证，再提取和验证准确版本。
`mise.exe` 与 `mise-shim.exe` 都受归属保护。已有受管安装的复用不再要求下载器存在。

`kai-download-acceleration` 的通用文件入口也默认 auto，保留 native mode、strategy、
selected、bytes 和 attempts。选中 origin 时不声明加速；选中网关仍需同窗证据。
探测已经读取的 origin 字节单独记录，不能仅凭 selected 将混合路径写成全网关。

在已选定的 Windows 目标任务环境中：

```bash
# KAI_KSCLI_BIN 指向该目标已有的可信客户端；通过其既有网关/Transport 执行。
bash skills/kai-tool-bootstrap/scripts/tool.sh plan mise
bash skills/kai-tool-bootstrap/scripts/tool.sh ensure mise

# 后续调用使用引导回执中的 mise 路径；每次任务重新建立环境。
export KAI_RUNTIME_ACCELERATION=required
bash skills/kai-dev-environment/scripts/runtime.sh install node 22.14.0 none
```

没有 ks-cli 时保留原生 zsetup 路径，并明确报告该 downloader。显式原包缓存仍可
用于离线操作，但不计为本轮在线选路成功。没有增加重复的代理、测速或下载实现。

## 原生实测与证据

测试拓扑为 Windows 原生 ks-cli → 既有可信 SSH 回环转发 → 控制端隔离 KSpeeder。
Windows 没有安装或启动 KSpeeder 服务，没有修改 Windows 默认代理。SDK 客户端
健康检查使用默认本机端点，因此除下载配置端口外，还补齐了测试健康检查转发。
最初未覆盖这些端点时的失败保留，没有以安装 Windows 服务解决测试接线问题。

| 路径 | 实际结果 | 同窗证据 |
| --- | --- | --- |
| mise 自身 | 新目录安装 2026.8.14；未用 ArchiveCache；auto → adaptive_race → admin_proxy | 33,633,582 字节，SHA256 与锁定官方 ZIP 相同 |
| 新 mise 安装 Node | Node 22.14.0 安装，实际运行断言 `process.version` | 元数据、34,906,389 字节原包、SHASUMS 和签名请求匹配 |
| npm 查询与使用 | 原生 npm view 精确版本；npm ci 保持锁；is-number 7.0.0 的版本与函数断言通过 | `/is-number` 与原包请求匹配；3730 字节原包通过冻结 SRI512 |
| 通用文件入口 | 新目录下载 mise ZIP；保留原始探测与选路摘要 | origin 探测读取 0 字节，admin_proxy 读取完整原包；SHA256 相同 |

Node 预期摘要另从官方 SHASUMS 获取，npm 原包另对照既有冻结 SRI512 校验。
四个 proof 都由公开 `evidence.sh` 核验，包含同实例、原生目标时间窗、实际监听、
成功响应、字节和摘要。主包、SDK 和 npm 三条使用链保持原验证；Windows npm
仍由通过 ks-cli Doctor/Explain 的环境与所选 node.exe/npm-cli.js 执行。

网关实例在测试中复用，**不宣称客户端与网关同时冷缓存，也不宣称加速倍数**。
同窗诊断原件、设备绑定、转发配置与服务状态只保存在仓库外。

## 三轮优化与自检

| 轮次 | 已定位的问题与修复 | 自检 |
| --- | --- | --- |
| 1 | 已有 mise 复用仍检查缺失的下载器；改为先校验受管安装，再为需要下载的路径准备客户端 | 原生失败先红后绿；6 项引导检查通过，包含错误 SHA 拒绝 |
| 2 | skill 入口增至 6719 字节，超过 6500 字节门禁；将 Linux 缓存细节移入平台说明，入口降为 6389 字节 | 失败的预算关联检查通过；42 个执行脚本与前候选相同 |
| 3 | 通用文件回执丢弃 origin 探测明细，严格证据不足；保留 native attempts 的类型与读取字节 | 回归先红后绿；R3 原生文件入口与第四条 proof 通过 |

没有第四轮产品优化。R3 与 R2 仅一个执行脚本变化；引导、SDK 和项目依赖代码
逐字节相同，保留 R2 的 6 项原生检查及完整使用链。R3 另实测改变的文件入口，
并逐项校验解压制品的 43 个 canonical 文件。

R2 有一次并发生命周期复测 180 秒超时，已回收子进程并保留失败。随后同代码串行
dry-run、安装、升级、卸载均通过；R3 串行复测也通过，约 37 秒。
尚未证实最初超时的确切原因，不将资源争用写成已确定根因。

- 最终本地 144 项：127 通过，17 项原生专用跳过；原生检查按上述范围另外执行。
- 16 项仓库检查通过；10 个 preset 生成、8 层 consumer 同步与来源锁核验通过。
- macOS 5 项、Windows 9 项原配置保持；Windows 默认代理仍关闭，20 项值摘要保持。
- 原 Windows mise 2026.7.0 保持；两机本任务进程为 0；隔离网关和两组转发均已停止。
- 本轮没有创建 Docker、改动 iStoreOS curl/库、修改信任库或发布生产制品。
  测试数据与超时 fixture 保留用于诊断。

最终候选为 `release/mise-acceleration-20261028-candidate-r3`，20 个归档，sourceState
为 worktree，未发布。manifest SHA256：
`c970c2ed82790b69a6c9fcfc04f3564c8cd2d0c28b67a629b363e5a51beb16f6`。
Windows 客户端与网关都是锁定摘要的测试来源，不代表桌面一键安装制品已发布。

## 保留的边界

1. WinGet 在线 CRL/OCSP 问题继续按用户要求暂缓，本轮没有进行 PKI 修复。
2. 网关对 npm 审计的两个 POST 端点返回 405。包查询、下载、SRI 和实际运行通过，
   **npm 审计结果未通过**，没有关闭原审计请求或隐藏失败日志。
3. 本轮新 mise 的实际 SDK 用例为 Node，项目用例为 npm；没有把历史 Python/Go/uv
   记录改写为这次重新验收。其他架构、桌面 Docker、真实 Agent 与正式客户端交付
   仍属于后续发布门禁。

MS0–MS10 与 macOS arm64 历史原生结果保持。
