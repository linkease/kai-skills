# Windows PKI 实施与三轮验收

结论：**PKI 组件已实现并通过原生测试；整体 WinGet 下载目标未通过，三轮后停止该路径**。
当前用户证书库可通过完整 CAPI 检查，但 WinINet 仍请求在线吊销服务并被重置。
本轮新增的 15 个持久对象已恢复；没有扩大到机器 CA 库、Root 库或默认代理设置。
机器摘要见 [实施结果](windows-pki-implementation-20261028-results.json)。

本页接续 [诊断与方案](windows-pki-20261028.md)。用户已授权完整实施任务树并最多循环三次。

## 明确目标、任务树和验收

本轮目标是实现独立 PKI 准备、检查、修复和恢复，并在保持默认代理及现有信任根的前提下，
打通原生 WinGet 安装包下载、原包校验和执行；下载安装分别验收。

| 任务 | 可测试的完成标准 | 本轮结果 |
| --- | --- | --- |
| 材料准备 | 从实际 TLS 叶证书动态发现 AIA/CDP，处理 PKCS#7 和交叉签名；连接到目标已有根；拒绝无效材料，不覆盖已有输出 | 通过本次三个主机的公开准备 CLI，得到 6 张证书、9 份 CRL |
| Plan / Check | Plan 无状态写入；验证签名、有效期、主机名和完整吊销；Check 只用当前用户已有存储 | 通过；Check 成功明确只表示 `current-user-capi-chain`，不表示原生下载成功 |
| Repair | 全量验证后只向 CurrentUser CA 添加对象；幂等、归属记录、持久意图日志和并发锁 | 通过公开原生生命周期测试，真实添加、复用、恢复 |
| Restore | 仅删除归属和内容都匹配的新增对象；保留原有及冲突对象；可重复恢复 | 通过，包括归属冲突和外来锁文件保留 |
| 原生端到端 | 实际 ks-cli / KSpeeder 认证、WinGet 查询与下载、冻结 SHA/size、程序烟测 | 未通过下载；没有进入原包校验、执行及安装验收 |
| 交付与保护 | 生成 preset、同步 consumer、仓库自检、原生检查、配置保持及资源清理 | 通过；候选未发布 |

## 实现入口与边界

canonical 文件位于现有 `common/skills/kai-tool-bootstrap`，沿用该 bootstrap 的跨平台布局，
原生入口显式要求 Windows 和 PowerShell 7.4+。其他平台不会误执行证书写入。

- `scripts/prepare-windows-pki.py`：可信控制端准备动态材料；需要现有 Python 环境中的 cryptography >=40。
- `scripts/windows-pki.ps1`：公开 `Roots / Check / Plan / Repair / Restore`。
- `resources/windows-pki.cs`：Windows 原生链、SSL 策略、CRL 签名和当前用户 CA 存储操作。
- `resources/windows-pki.md`：准备、调用、有效期、恢复和验收边界。
- `tests/multisystem/test_native_windows_pki.py`：真实 Windows 的公开入口回归。

Repair 不注册信任根，不替换旧对象，也不由 ks-cli 隐式触发。每份 CRL 在链检查之前独立验证签名和时间，
避免旧缓存掩盖无效的新输入。新增上下文带独立归属属性；写入前刷新持久意图日志，
恢复时同时核对对象摘要和归属。锁由独占文件句柄控制；归属标记文件保留，释放句柄即可再次获取，
不在关闭后按路径删除可能已被其他进程替换的文件。外来锁文件保留并报错。

无效材料、未知根、归属冲突和不足的剩余有效期均明确失败。OCSP-only 的发行者需要提供其公开 CRL URL；
当前实现不宣称任意 OCSP 获取能力，也不把时效性 CRL 固定打入归档。

## 三轮实施与定位

| 轮次 | 工作和实际反馈 | 判定 |
| --- | --- | --- |
| 1 | 实现组件、建立公开入口红绿回归；原生生命周期和保护测试通过；动态生成三个主机的 15 个材料并真实 Repair。源更新退出 0 但输出 `Cancelled`，随后查询在前置 CONNECT 失败 | 组件通过，端到端未通过；取消不计成功 |
| 2 | 独立认证前置检查通过；原生 show 退出 0、目录命中缓存。下载仍返回 `0x80072f19`；新增已有存储 Check，三个主机均通过严格 CAPI 检查 | 证明当前用户 CAPI 健康不能替代 WinINet 验收 |
| 3 | 不终止 TLS 的诊断转发记录 WinGet 实际叶证书，确认与准备的 GitHub E36 证书完全相同；同一原生 WinINet API 返回 12057，CAPI2 明确记录在线 CRL/OCSP 读取被重置 | 最终未通过；停止继续优化下载路径，Restore 15 个对象 |

客户端仍为前轮已校验的 ks-cli candidate，owner commit
`32cbbaa8aa0f3fce35b32c3d9497236e136678f5`，没有改客户端或生产网关。
KSpeeder 使用既有认证 CONNECT，TLS 始终由原生客户端与原站建立；诊断只读取 TLS 1.2 明文握手中的公开证书，
没有解密应用数据或替换原站证书。

对照实验确实发现同域名可按 TLS 客户端收到 E36 或 R36 证书，但本次实际 WinGet 收到的 E36 与准备材料一致，
所以这不是本次失败的解释。额外 RSA 材料准备探索未取得完整有效 CRL 集合，记录为失败，没有纳入交付路径。

## 剩余阻塞的证据

同一用户中：当前存储的 `CertGetCertificateChain` / SSL 策略可成功；WinINet `InternetOpenUrl` 返回 12057。
只采集该诊断子进程的 CAPI2 事件，共 18 条。其中在线请求包括：

| 官方 PKI 服务 | 原生反馈 |
| --- | --- |
| `crl.sectigo.com` | HTTP CRL 读取连接异常 |
| `ocsp.sectigo.com` | HTTP OCSP 读取连接异常 |
| `crl.usertrust.com` | HTTP CRL 读取连接异常 |
| `ocsp.usertrust.com` | HTTP OCSP 读取连接异常 |

事件记录 `CRYPT_E_REVOCATION_OFFLINE` / `0x80092013`，网络返回 `0x2EFE`，随后 WinINet 返回 12057。
这证明本次 CurrentUser CA 修复不足以解决该 WinINet 在线验证路径；
**没有证据证明简单改写 LocalMachine CA 或再增加相同材料就能解决**，因此没有越界尝试。

CAPI2 Operational 日志原来关闭，本轮诊断临时启用，结束后已恢复关闭。
过程错误与语义失败分别保留：初次测试脚本语法错误、缺失入口的有效红灯、编译警告混入 JSON 后的修正，
以及代码仍在变化时误启动的过宽里程碑检查。后者已停止，其生成目录不一致结果不计本轮验收。
该过宽调用还尝试了 12 个 lab case，均在缺少 KAI_LAB_CONFIG 时被配置检查拒绝，没有创建远程资源；不计为系统测试成功。

## 最终自检与交付

- 原生公开入口 7 项通过：无写入 Plan、真实修复/复用/恢复及当前存储检查、有效期刷新要求、归属冲突、Root 输入拒绝、错误 CRL 签名拒绝、外来锁文件保留。
- 本地 unittest 134 项发现，123 通过、11 个原生专用跳过；本轮 7 项原生测试另已执行。
- 16 个仓库架构、安装、上下文及 Transport 合约检查通过，包括实际 Reasonix loader；Go 检查使用 SSD wrapper。
- 10 个 preset 重新生成，8 个 consumer canonical 层同步，生成一致性和来源锁检查通过。
- 通用 skill-creator 校验器不接受本仓库原有的 owner/systems/triggers 等扩展字段，不能作为本仓库 frontmatter 验收；字段保留，以仓库契约和实际 loader 为准。

候选为 `release/windows-pki-20261028-candidate`，20 个归档，sourceState 为 worktree。
最终原生测试的 PowerShell/C# 文件与 canonical 来源一致；没有发布、推送或替换生产客户端。

最终 Restore 移除本轮 15 个对象。CurrentUser Root/CA、LocalMachine Root/CA 的证书集合恢复为原样，
数量为 82/59/81/26。Windows 默认代理的 20 项注册表值保持；WinGet 显式代理选项仍按既有授权启用。
macOS 5 项、Windows 9 项原配置文件保持；两机任务进程为 0。
测试网关、诊断转发及全部临时 SSH 转发已停止，本轮没有运行 Docker。
原生测试资料、恢复日志及私有证据保留在仓库外。

## 下一步范围

整体目标仍为 **partial**，不进入安装验收。
下一阶段应定位并恢复这台 Windows 对官方 PKI 服务的可达性，优先检查上述 HTTP CRL/OCSP 请求
在端点或网络出口何处被重置，再生成针对该设备的定向放行方案；继续保持默认代理和信任根不变。
该网络出口修复不是本轮 CA 缓存操作的隐式扩展，需要另开范围继续；本轮三次优化已用完。
