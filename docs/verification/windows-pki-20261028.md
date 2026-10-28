# Windows 证书问题定位与修复方案

后续已完成组件实施：当前用户 CA 修复通过，但原生 WinINet 在线吊销访问仍失败。
完整结果及三轮停止点见 [实施与验收](windows-pki-implementation-20261028.md)。本页保留内存原型阶段的事实。

结论：**已有不改变默认代理、不新增信任根的可行修复方向，并已在 Windows 原生证书验证层通过**。
缺少的中间证书和有效吊销材料补入进程内存后，CDN 与 GitHub 的完整链、吊销及 SSL 主机名策略均通过；
破坏吊销列表签名后均拒绝。本轮没有把材料写入系统证书库，尚未据此重测原生 WinGet 下载。
证据见 [机器结果及修复计划](windows-pki-20261028-results.json)。

本页接续 [显式代理原生验收](winget-cli-20261028.md)。用户要求继续确认解决办法；本轮先把修复依据和产品边界做成可复查结果。

## 任务树和验收

1. 精确区分链缺失、吊销材料缺失和网络读取错误。
   验收：读取目标原有信任库；比较同机 WinHTTP、curl 对官方 PKI 地址的请求；校验辅助材料能否连接到原有信任根。
2. 用原生 API 验证材料修复是否有效。
   验收：基线、仅中间证书、完整材料及损坏签名四种场景有不同且正确的结果；完整检查包括吊销和 SSL 主机名，不依赖关闭校验。
3. 核对保护范围并给出下一阶段实施方案。
   验收：默认代理和 Root/CA 四个证书库前后相同；不将内存原型误报为 WinGet 下载成功；修复有过期处理和恢复边界。

上述三项已完成；下一阶段缓存写入和原生下载验收尚未执行。

## 新确认的事实

Windows WinHTTP 默认配置为直连。对以下三类地址显式直连，WinHTTP 均返回连接异常：
Microsoft 中间证书、Microsoft 分区 CRL、Sectigo 中间证书。同机 curl 对两个证书地址也返回 56、HTTP 000、0 字节。
这排除了“仅 WinHTTP 客户端失败”的解释；具体是端点、链路还是网络策略导致重置，本轮未进一步归因。
控制端可从官方地址取得相同 PKI 对象。

目标原有 Root 已包含可用信任锚；以下四张证书在目标 Root/CA 库中均缺失：

| 辅助证书 | 上级 |
| --- | --- |
| Microsoft TLS G2 RSA CA OCSP 04 | Microsoft TLS RSA Root G2 |
| Microsoft TLS RSA Root G2（交叉签名版本） | DigiCert Global Root G2（目标已有） |
| Sectigo Public Server Authentication CA DV E36 | Sectigo Public Server Authentication Root E46 |
| Sectigo Public Server Authentication Root E46（交叉签名版本） | USERTrust ECC Certification Authority（目标已有） |

名字含 Root 的两个交叉签名版本在这条路径中是中间证书，不应导入 Root 库。
Sectigo 的旧系统交叉签名路径可核对其 [官方层级说明](https://www.sectigo.com/knowledge-base/detail/Sectigo-new-Public-Roots-and-Issuing-CAs-Hierarchy)。

从叶证书 AIA 和后续发行者路径取得原始材料。部分官方 `.crt` 地址实际提供 PKCS#7 集合，需解析全部候选，
根据发行者、签名和目标已有根选择路径，不能按后缀或 Subject 字符串直接认定信任。
已验证四张辅助证书逐级签名，两条链均可连接到从目标导出的原有信任根。

另取得 6 份官方 CRL：分别覆盖两个叶证书及四个辅助 CA 证书。所有对象均校验签名、有效期及目标序列号状态。
GitHub 叶证书只有 OCSP 地址；本次取得发行 CA 的有效 CRL，并由 Windows 原生链引擎实际接受，不由自写逻辑代替吊销判断。
这些 CRL 是有时效的数据，不是永久依赖锁；本次最早到期时间为 2026-11-04 05:39:56 UTC。

## Windows 原生验证

同一公开 Transport 启动独立 PowerShell 7 进程，调用 Windows `CertGetCertificateChain` 和
`CertVerifyCertificateChainPolicy(CERT_CHAIN_POLICY_SSL)`。
中间证书及 CRL 只放进 `CERT_STORE_PROV_MEMORY`，Root 使用目标原有系统信任；
开启除根以外的完整吊销检查，检查实际主机名，禁用自动补根和 AIA 网络读取，只使用现有缓存与提供的材料。
离线取数限制不会跳过吊销检查：材料不足必须失败。

| 输入 | CDN | GitHub |
| --- | --- | --- |
| 只有叶证书及原有系统库 | 失败：链不完整及吊销状态未知 | 同左 |
| 增加四张辅助证书 | 失败：吊销离线 `0x80092013` | 同左 |
| 再增加六份有效 CRL | 链错误 0、SSL 策略错误 0 | 同左 |
| 新进程中破坏对应叶证书 CRL 签名 | 拒绝：`0x80092013` | 同左 |

负向检查在新进程执行，避免复用前一次成功结果的进程缓存。
因此可确认：**已有根信任足够；有效辅助材料能够解决本次证书层阻塞**。
这一结论不等同于“已写入持久缓存”或“原生 WinGet 已下载成功”。

微软说明原生链引擎会查找缓存或系统存储中的有效吊销材料，再尝试网络，见
[Crypt32 吊销语义](https://learn.microsoft.com/en-us/windows/win32/seccrypto/certificate-revocation-list-semantics)。
原生链 API 的缓存检查和附加存储边界见
[CertGetCertificateChain](https://learn.microsoft.com/en-us/windows/win32/api/wincrypt/nf-wincrypt-certgetcertificatechain)。

最初两次将大批原型材料嵌入 Transport 脚本的实验超时，未进入可见的验证阶段，未计为证书失败或成功。
改为可信 SCP 传输原型及数据，再由短命令调用，完成上述原生验证。
curl 首次探针亦受 PowerShell 错误处理影响；保留失败记录，最终以独立捕获的两个 curl 退出码及统计判断。

## 推荐实施方式

将 Windows PKI 健康与修复放在 Windows System Pack 的 bootstrap 中，作为独立、显式操作；
ks-cli 继续只负责命令范围网络中继，不在每次 WinGet 调用时隐式改证书库。

下一阶段任务树和验收如下：

1. 实现只读检查和修复计划。
   动态发现实际目标主机的链、AIA/CDP 和已有信任，列出缺失对象、有效期及下载来源。
   验收：Plan 无写入；未知信任根、无有效吊销材料、错误签名和过期材料均明确失败。
2. 实现当前用户 CA 辅助缓存修复和恢复。
   通过可信传输及明确下载端点获取材料，先在内存中按原有 Root 完成原生验证，再写入 `CurrentUser\CA` 的辅助证书/CRL。
   不写 Root，不替换原有对象；记录本次新增对象的精确摘要，恢复时只删除仍匹配的本次新增对象。
   验收：签名、期限、适用范围和 SSL 策略通过；Root 和代理摘要不变；重复执行幂等；恢复保留原有对象。
   如遇实现不支持的存储/更新情况，应失败并保留对象，不改用关闭吊销检查。
3. 再验收完整原生命令。
   测 `ks-cli winget show/download`，检查源自动更新警告是否消失；冻结 jq 原包大小/SHA及运行烟测。
   验收：原生命令成功、有实际中继流量、原包校验通过；在此之后才进入受控安装/移除验收。

CRL 要按有效期重新取得并验签，不能把本次六份数据永久打进 skills，也不能失败后延长其有效期。
官方 PKI HTTP 对象可经可信传输取得，但它们的真实性最终仍由发行者签名和目标原有信任证明。
镜像或跨协议获取不能代替这一步。新增主机、证书轮换或其他发行者必须重新规划，不能只硬编码这次两个域名。

恢复官方 PKI 地址的网络可达性仍是更长期的系统解决办法；缓存修复可以在默认代理不变的约束下开展验证，
但不能宣称修好了所有 Windows 系统网络访问。

## 保护与状态

CurrentUser Root/CA 和 LocalMachine Root/CA 的证书集合前后完全相同，数量依次为 82/59/81/26。
20 项默认代理注册表值摘要相同，默认代理关闭；WinHTTP 保持原来的直连配置。
本轮未运行测试网关或 Docker；原型数据保留在任务目录，绑定、原始日志和对象清单保存在仓库外私有归档。
未安装系统应用，未导入中间证书、CRL 或信任根，没有公开发布。

桌面发布仍为 partial；当前状态是 **证书层修复原型通过，等待辅助缓存实现及原生下载复测**。
