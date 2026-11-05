# Windows 官方目录刷新与联网归因

本批在用户明确同意继续后开展，最多三轮优化。缺失依赖首次安装、升级及多层图属于未覆盖项，不以当前机器已有共享运行库构造虚假的首次安装测试。

## 任务树与验收标准

1. 固定候选程序与目标基线：复用 `f5665424` 验证构建，核对远端 SHA256；记录官方源身份、注册目录版本、服务、PATH、代理及证书信任配置摘要。
2. 复现原生刷新：单独执行原生 WinGet 官方源更新，保存归属目录内的诊断，区分网络、证书和目录部署错误。验收依据是本次调用结果及目录版本，缓存安装成功不代替刷新成功。
3. 验证正式恢复入口：执行 `ks-cli --json winget source update --name winget --disable-interactivity`，要求官方包获取、原生身份/签名验证、注册状态以及更新前后版本证据完整；等版本复用与实际版本更新分别记录，原站直连与加速选路分别记录。
4. 定位联网边界：根据本次错误进行只读定向检查，保留 fresh CRL/OCSP 与缓存验证的区别；未做不同机器/网络的对照时，不宣称机器或网络归因完成。
5. 自检：确认服务、PATH、默认代理和信任配置保持，停止临时程序及端口，发布脱敏结果。失败最多优化三轮；涉及产品语义或超出授权的环境改造时停止相关动作。

不实现 CONNECT，不清空全机证书缓存，不降低吊销或 TLS 验证，不卸载既有 VC++ 以模拟干净机器。原始日志和连接配置保留仓库外。

## 执行结果

通过正式 ks-cli 的目录恢复与业务 skill 刷新/查询验收，未修改程序实现。使用一轮产品实测；准备阶段的变量遮蔽、探针布尔序列化和测试断言的回执层级均为私有测试脚本问题，原始失败记录保留，修正后不重写原始捕获。结构化证据见 [机器结果](windows-source-refresh-20261105-results.json)。

原生 `winget source update` 输出 `Cancelled` 但退出码为 0。日志证明两次原始目录下载完成，SHA256 与正式恢复取得的原包相同；Microsoft 证书链与 MSIX 信任验证均返回 0。失败发生在 `AddPackage` 部署，HRESULT 为 `0x80070520`，即 [ERROR_NO_SUCH_LOGON_SESSION](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--1300-1699-)。因此本次并非目录无法下载或签名验证失败，证据指向当前原生部署/登录会话路径；未切换机器或登录类型，不能认定所有 SSH 会话或 Windows 机器均有此问题。

随后正式 `ks-cli --json winget source update --name winget --disable-interactivity` 成功下载并通过普通 Windows 部署，把官方 Store 签名源从 `2026.1029.201.55` 更新到 `2026.1105.1439.51`，原包 SHA256 为 `0eca41c759218f75b922f9e51faaad6675387823be5e77e29a3b777a0cec3636`。这是实际版本更新，不是等版本复用。它与 Microsoft [官方排障文档](https://github.com/microsoft/winget-cli/blob/master/doc/troubleshooting/README.md)提出的原始官方目录包恢复方向一致。

独立封装的 `kai-software` 实际执行 `software.sh refresh winget` 成功，保留内层 `nativeResult` 正式回执；此时为已更新目录的等版本复用，分别记录。随后原生 WinGet 精确查询 PuTTY 0.85.0.0 以及 skill 的 info 查询均成功，未出现本次可见的更新失败警告。没有以查询成功推断未来的原生自动更新不再失败。

## 证书联网与加速边界

Windows 原生 `CryptRetrieveObjectByUrlW` 对三个历史失败 CRL 地址本次全部获取成功：Microsoft TLS G2 RSA CA OCSP 04 的 Partition00099、Sectigo CADVE36 和 USERTrust ECC。使用 `CRYPT_WIRE_ONLY_RETRIEVAL | CRYPT_DONT_CACHE_RESULT`（0x0c），[原生 API 契约](https://learn.microsoft.com/en-us/windows/win32/api/wincrypt/nf-wincrypt-cryptretrieveobjectbyurlw)明确绕过 URL 缓存且不写入该缓存。没有清空全机缓存或安装证书。这关闭“这些历史 URL 当前仍无法原生联网获取”的判断；CRL 获取不包含完整链的签名/时效/吊销验收，更不包含 fresh OCSP 请求，二者继续标为未验证。

本次下载选择 `origin`，不是加速命中。Windows 候选网关对目录请求返回 502，其上游 HEAD 记录为 404；控制机同一公开上游的 HEAD/范围 GET 为 403，而官方源为 200/206。不同环境结果分开保留，不能把控制机 403 当作 Windows 404 的同一原因。当前公共上游路由尚未完成加速验收，不能用健康的本地网关替代上游可用性；本批未部署服务器、绕过授权或更换代理。

## 自检和剩余覆盖

8 项独立包契约、8 项 WinGet 适配契约通过，无跳过；生成一致性通过。skill 参考文档已补充原生退出码 0/Cancelled 的误判边界及部署错误归类，并由源码重新生成独立包和系统集合。

最终原机审计：既有服务及程序 SHA256、用户和系统 PATH、WinINet/WinHTTP 代理配置、CurrentUser/LocalMachine 的 Root/CA 证书集合保持；临时网关已停止、测试端口清理。官方目录版本更新是本次明确授权的预期变更。

缺失依赖首次安装、升级、多层图仍需干净 Windows 环境，不能删除当前机器共享运行库来模拟。完整 fresh CRL/OCSP、上游加速路由和多系统集合等验收仍待完成；BM9 release-ready=false，BM10 未发布。
