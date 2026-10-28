# WinGet 显式代理原生验收

后续已确认中间证书及有效吊销材料可使 Windows 原生链检查通过，见
[PKI 定位与修复方案](windows-pki-20261028.md)。本页保留前轮原生下载失败的事实。

结论：**已按用户授权开启 WinGet 显式代理；原生查询通过，安装包下载未通过**。
三轮定向验证与优化尝试后，下载仍被 Windows 证书吊销检查阻塞，本轮停止该路径。
没有更改 Windows 默认代理。逐项摘要和证据摘要见
[机器结果](winget-cli-20261028-results.json)。

本页接续 [SDK 查询加速报告](winget-acceleration-20261028.md)，保留前轮事实。
前轮待决动作已获用户明确授权并执行：

```powershell
winget settings --enable ProxyCommandLineOptions
```

## 任务树与验收

1. 开启并验证显式代理选项。
   验收：原生设置读取为 true；除该选项外，WinGet 管理设置一致；Windows 默认代理一致。
2. 通过真实 KSpeeder 执行原生查询和固定版本安装包下载。
   验收：公开 `ks-cli winget` 命令退出 0，有认证及实际数据流量；原包与冻结 SHA/size 一致，执行烟测通过。
3. 自检、同步技能说明并清理测试资源。
   验收：生成 preset 和 consumer 一致；配置保持检查通过；任务网关、Docker 和转发归零。

第 1、3 项通过。第 2 项仅查询通过，下载及原包执行验收未通过；不将本轮标为完整通过。

## 实际执行与三轮结果

使用既有 ks-cli candidate，owner commit
`32cbbaa8aa0f3fce35b32c3d9497236e136678f5`；未修改客户端或网关实现。
KSpeeder 复用原有认证 CONNECT，原站 TLS 保持端到端。

| 操作/轮次 | 实际结果 | 判定 |
| --- | --- | --- |
| 开启选项 | 命令退出 0；官方模块读取 false → true | 通过 |
| `ks-cli winget show --id Microsoft.PowerShell --exact --source winget` | 退出 0；2 个数据隧道，29346 下载字节，约 52.8 秒 | 原生查询通过；同时存在源自动更新失败警告，不能据此声称索引已刷新或结果为最新版本 |
| 初次 jq 1.8.2 下载 | 元数据读取失败，`0x80072efe`；1 个隧道，9362 下载字节 | 未开始原包下载 |
| 第 1 轮：相同命令复测并对比网关出口 | 取得 jq 1.8.2 元数据并进入 GitHub 下载，随后 `0x80072f19`；4 个隧道，32921 下载字节 | 失败；Docker 出口访问 GitHub 另有 35 秒超时 |
| 第 2 轮：仅切换到可完整取得同一原包的控制端出口 | 首次前置 CONNECT 超时，原生命令未启动；随后独立前置认证通过，再测仍为 `0x80072f19`；2 个隧道，5877 下载字节 | 失败；不能仅归因为原 Docker 出口 |
| 第 3 轮：原生证书检查、正常在线缓存刷新尝试后复测 | 原生证书工具报告 WinHTTP 取证错误、链不完整和吊销状态未知；最终下载仍为 `0x80072f19`，2 个隧道，5876 下载字节 | 失败；三轮上限后停止 |

固定下载参数为 `jqlang.jq` / `1.8.2` / `x64` / 原注册 `winget` 源，目标是任务数据目录中的新目录，包含中文和空格。
未使用本地替代 manifest，未执行忽略 hash 或证书检查的选项，未安装或卸载设备现有应用。
本轮未获得 WinGet 成功下载的原包，因此没有执行预定的冻结 SHA/size 比对和程序烟测。
控制端 curl 完整读取同 URL 的 1035264 字节，只能证明该出口可达，不能替代 Windows 原生命令验收。

## 已定位的边界

`0x80072f19` 对应 WinINet 错误 12057：证书吊销检查失败，见
[微软错误码说明](https://learn.microsoft.com/en-us/windows/win32/wininet/wininet-errors)。
Windows 对通过正常 TLS 获取的 CDN/GitHub 叶证书执行 `certutil -verify -urlfetch`，
实际报告 `CRYPT_E_REVOCATION_OFFLINE`、`CERT_TRUST_IS_PARTIAL_CHAIN`、
`CERT_TRUST_REVOCATION_STATUS_UNKNOWN`，并有 WinHTTP URL 读取连接错误。
两次 certutil 进程均退出 0，但输出含上述错误，因此证书验收为失败。
该诊断没有导入证书、添加信任根或关闭吊销检查。

现有证据表明：**WinGet 自身显式代理已可用，不足以证明 Windows 的证书链与吊销服务均可达**。
源索引自动更新也仍有连接重置。尚未证明这些系统网络请求均遵循 WinGet 的显式代理，
不把它们当作已经通过中继的请求。后续修复需要分别验证 issuer/AIA、CRL/OCSP 和源更新路径，
继续保留默认代理及完整证书检查。

微软明确将原生代理用于目录和安装包下载；安装程序自身的网络请求另有边界，见
[官方代理设计](https://github.com/microsoft/winget-cli/blob/master/doc/specs/%23190%20-%20Proxy%20Support.md)。
Kai 的 required 适配器仍只验收 search/info；本轮不扩大 install/remove 支持声明。

## 交付、自检和清理

技能 canonical 参考说明新增显式选项开启方式、原生命令示例及证书错误识别，
已重新生成 10 个 preset，8 个 consumer canonical 层已同步并检查。
catalog、Windows 合约、实际 Reasonix loader 和 diff 检查通过。
没有运行时代码变更；前轮运行时回归证据继续保留。

新的说明候选为 `release/winget-cli-20261028-candidate`，20 个归档，sourceState 为 worktree。
该候选包含说明更新；本轮原生测试使用前轮已校验的相同执行代码和客户端二进制。
旧候选和旧验收记录保留；没有公开发布。

WinGet 管理设置只改变获授权的 `ProxyCommandLineOptions`，WinGet 默认代理保持原值。
Windows 20 项默认代理注册表值摘要前后一致，代理仍关闭。
macOS 5 项、Windows 9 项既有配置文件保持；两机任务进程为 0。
隔离 Docker 容器、网络、镜像，以及两组测试转发和控制端测试网关均已清理。
设备数据盘测试资料保留，绑定配置、认证材料和原始日志在仓库外私有归档。

完整桌面发布结论仍为 **partial**；本轮没有证明原生 WinGet 下载安装通过。
