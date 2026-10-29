# WinGet 正式入口候选与原生验收（2026-10-29）

本轮实现并提交 ks-cli 原生准备流程及官方源恢复入口。Windows AMD64、WinGet
v1.29.380 已通过签名 EXE/MSI 下载、原始 SHA256、原生导出与实际安装/运行/卸载；
**完整依赖链路仍未通过**。三轮实施优化已用完，不继续第四轮；未发布或推送。

## 任务树与结果

| 任务及验收标准 | 自检结果 |
| --- | --- |
| WinGet 原生确定官方清单；缺失元数据时不下载、不安装 | 通过；预检后拒绝源请求的原机测试无原包获取和安装 |
| 优先 auto，失败时显式可信 CONNECT 获取同一 HTTPS 原包；保留 SHA256 | jq 选择 admin_proxy/adaptive_race；PuTTY/Python 选择 trusted_connect；不声称兜底为竞速 |
| 签名 MSI/EXE 原包及原生使用 | PuTTY 0.83.0.0 MSI、Python 3.12.10 EXE 签名 Valid、SHA256 匹配，保留 MOTW |
| 实际安装、版本运行与回收；保留原有软件 | PuTTY/plink、Python/pip 使用通过；测试注册项和主程序均已卸载，Python 用户 PATH 不变 |
| 元数据无法刷新时，恢复同一个官方签名源包 | 原始 source2.msix 经原生 AppX 部署更新源包；URL/身份/信任不变；正式命令的等版本复用通过 |
| 真实依赖原包准备及安装 | 未通过；源更新解决旧清单 404，随后 VC++ 原包获取超时，未执行安装或升级共享运行库 |
| 本地及原生回归与分发校验 | Linux 完整 app 测试及 WinGet race 通过；全部 WinGet Go 测试在 Windows 通过；10 预设、catalog、6 项分发测试通过 |

## 元数据失败的处理

原有官方源包为 `2026.708.1025.14`，已明显过期。缓存中部分包可查询，但 VC++
依赖清单返回 HTTP 404。原生 `source update` 曾退出 0、输出 `Cancelled`，不能计为刷新成功。

从官方 HTTPS CDN 获取未修改的 source2.msix，Windows 原生 AppX 验证并更新至
`2026.1029.201.55`，源 URL、类型、身份及信任级别保持不变。对应正式候选命令为：

```powershell
ks-cli --json winget source update --name winget --disable-interactivity
```

该命令优先 auto、失败时复用显式可信 CONNECT，要求原生已注册的 Microsoft Store
源包身份与签名类型。仅部署更新版本；等版本使用已有原生签名包，拒绝降级、强制及无签名部署。
本次正式命令回执为 `deployment=reused`：实际新版本部署来自此前的原生恢复步骤，
不能将两项证据混为正式封装再次部署新版。新接口保留了此区别及前后版本。

清单仍不完整时，下载/安装入口停止，不编造地址或 SHA，不改源身份。回执中的
`failed-native-cache-used` 仅描述本次原生刷新探测失败、仍可使用原生元数据；它既不表示
整个目录网络健康，也不抹去独立原生源包更新的证据。

## CRL/OCSP 的关系

Windows 证书链、CRL/OCSP 检索属于独立系统网络流程，不能假定继承 WinGet 会话代理。
之前 Windows 直连同一 CRL/AIA 地址也重置，而控制端可取回；这排除了“只有 ks-cli
才会触发故障”的解释，仍未定位具体重置设备。CONNECT-only 通道也不覆盖普通 HTTP GET/OCSP POST。

本轮保留默认代理、证书存储及吊销策略。签名 Valid、原生安装成功和官方源恢复，均不等于
系统新的在线吊销查询已健康；native HEAD/version 探测仍保留为独立未通过门禁。

## 剩余事项与证据边界

VC++ 14.51.36247.0 原包域名尚无自动路由，Windows direct/CONNECT 获取仍超时，
完整依赖导出与依赖安装不能宣称通过。复杂分支依赖图、其他桌面架构亦未验收。
Kai accelerated SDK helper 的 search/info 范围保持原样；正式 CLI 候选属于独立入口，
未自动启用未通过的通用安装分支。npm audit、桌面正式制品等历史门禁不受本轮结果替代。

初期发现并固定了 Windows 路径边界循环、未匹配路由原站兜底、原生依赖日志顺序以及
PowerShell 7 模块路径继承问题。MSI 的斜杠参数和并发卸载 1618 是测试脚本问题，修正并保留失败证据。
泛用 skill-creator validator 不接受本仓库已有的扩展 frontmatter；本仓库 catalog 与生成/分发检查通过。

完整结果、候选 SHA256、来源提交及证据摘要见
[JSON 回执](winget-preparation-20261029-results.json)。设备绑定、凭证、私有路径、
原始日志和测试程序保存在仓库外，成功和失败证据均保留。

参考：[WinGet 源包验证及部署实现](https://github.com/microsoft/winget-cli/blob/v1.29.380/src/AppInstallerRepositoryCore/Microsoft/PreIndexedPackageSourceFactory.cpp)、
[Microsoft CRL/OCSP 检索语义](https://learn.microsoft.com/en-us/windows/win32/seccrypto/certificate-revocation-list-semantics)。
