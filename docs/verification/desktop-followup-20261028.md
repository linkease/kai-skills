# 桌面遗留问题后续修复

后续已用真实 kspeeder 打通 WinGet 官方目录查询，见
[WinGet 加速报告](winget-acceleration-20261028.md)。本页保留当时事实。

承接 [上一轮三轮专项](desktop-optimization-20261028.md)，本轮重新获得继续修复授权。
历史报告不改写。目标绑定、原生日志及信任材料保存在仓库外。

任务树与验收：

1. jq owner 原生 PS5 入口：先复现公开生成入口，再修改维护源并重建。
   验收：PS5/PS7 的 help、plan、空参数、字面参数和退出码；真实卸载入口。
2. WinGet structured provider：比较线程模型、模块兼容、源数据及属性读取。
   验收：精确 ID、非空真实版本、来源验证、已安装状态；错误不能冒充成功。
3. 交付同步：owner 来源锁、生成 preset、Kai consumer 和原生/本地回归。
   验收：制品及证据摘要可核验，测试进程已回收，不更改系统 curl 或网络策略。

每条路径最多三轮优化；三轮仍失败则记录阻塞并停下该路径。
本轮未包含公开发布或生产网关升级。

结论：**partial**。jq 的 PS5 原生参数问题已修复；WinGet 空版本误报已修复，
真实联网查询仍受官方 CDN 连接重置阻塞。[逐项机器结果](desktop-followup-20261028-results.json)
保留成功、预期失败和测试环境失败，未将错误处理通过计为联网查询通过。

## 三轮实施与验收

| 轮次 | 实施及发现 | 自检 |
| --- | --- | --- |
| 1 | owner 公开生成入口在 PS5 的 help 重现 Bash `unexpected EOF`；WinGet 比较 PS5/PS7、STA/MTA，并串行复查 | PS5 原始入口为红；改变 apartment 未证明可解决 WinGet |
| 2 | owner 维护源改用 ProcessStartInfo 和 Windows CRT 参数引用；WinGet 拒绝 null/空白版本 | PS5/PS7 字面参数及退出 37 通过；WinGet 6 个失败子场景先红后绿；官方原生日志定位到 CDN 的 InternetOpenUrl 连接重置 |
| 3 | 同步原始 owner 资源与锁、重建 preset、最终制品原生复测 | jq 两个 PowerShell 引擎通过；PS5 真实安装/复用/卸载通过；最终 Windows 入口明确返回 11/catalog-unavailable；联网查询门禁仍未通过 |

jq 根因是 PS5 对 Bash `-c` 内嵌双引号和空参数的 native binder 处理。
修复维护源 `zsetup-scripts/jq/windows.ps1`，由既有 `jq/build.py` 生成公开入口；
继续运行同一份 POSIX 安装策略，没有增加下载器或改动生成资源的独立实现。
测试提交与实现提交分开；实现为 owner commit
`748e92eb0641d6e3d20b8a394ff3a1a65d0c9a86`。
owner 仍有本轮前已存在的候选修改，消费锁保留 `local-candidate`，不宣称 clean release。

公开入口验收包含 help、plan、空参数拒绝、中文/空格/引号/反斜杠/表达式字面值
以及真实 native exit 37。PS5 完整生命周期使用已核对官方 SHA/size 的 jq 1.8.2
文件，先放入新的受管版本目录，再由原 installer 通过 native core 0.4.0 验证、
安装、重复安装并卸载。此项是缓存路径的原生生命周期证据，不冒充本轮在线冷下载。
最终确认用户 jq 命令消失，原 fixture 和系统 jq 保留。

WinGet 根因的证据比上一轮更具体：原生日志反复记录 `0x80072EFF`、
`InternetOpenUrl() failed`，涉及 `cdn.winget.microsoft.com/cache` 的 source 更新及
PowerShell 包的 `versionData.mszyml`。原生 HEAD 探测也失败。设备系统代理关闭，
无命令环境代理；没有调整代理、DNS、hosts、证书或 WinGet 源。
这些证据支持“官方 CDN 请求连接重置”，尚未确定上游网络中哪个环节实施重置，
不能断言 COM 或客户端版本本身损坏。

修复另一个确定的代码缺陷：PowerShell 的 `@($null).Count` 为 1，原数量判断会
继续访问 Source，误报来源冲突并可能触发更多联网读取。现在 null/空白版本均
返回 `catalog-unavailable`，保留非空版本时的精确 ID/来源检查。最终制品的真实
`software.sh info winget:Microsoft.PowerShell` 返回 11 和结构化不可用原因。
原生查询自身仍可能等待网络重试；本轮的远程执行保留 Transport 总超时保护，
不宣称所有网络故障都能立即返回。

## 最终制品和验证

候选目录：`release/desktop-followup-20261028-candidate`，共 20 个归档。
manifest SHA256：`d72e5124377681a43052f93b337d591650e3933fe7a9321d6646202d0225e331`。
sourceState 为 worktree；两平台选定归档摘要、treeDigest 和逐项日志摘要见机器结果。

- 本地 124 项：122 通过、2 项原生专用跳过；原生检查另行执行。
- 16 个架构/安装/契约检查通过；10 个生成 preset、8 个 consumer 层和 owner 锁通过。
- owner 完整 `check.sh` 通过，使用 canonical Rust 的 0.5.0 检查包；Windows 原生
  测试仍使用已发布 0.4.0，未替换为未发布的桌面核心。
- 最终归档的 macOS/Windows 安装、升级、卸载通过；macOS APFS 检查通过；
  最终归档内的 jq owner 入口在 PS5/PS7 均通过。
- Windows 生命周期首次因测试 PATH 缺少 fixture jq 而失败；补齐声明的前置依赖
  后原测试通过，没有为此修改产品实现。测试启动器的命令长度和 PS5 JSON 数组
  转换问题也分别修正，未计为产品优化失败。
- macOS 5 项、Windows 9 项配置摘要保持一致；两台设备本任务残留进程为 0。
  本轮未创建 Docker/网关/转发资源，未触及 iStoreOS curl 或生产服务。

## 保留门禁及后续方案

WinGet 的**成功联网查询**仍是唯一原有桌面门禁，三轮后停止该路径。
下一步先恢复官方 CDN 的可信出网条件，再运行原公开 structured 查询及精确版本验收。
若需新增 WinGet 代理能力，应单独确定适配边界：现有公共模块没有逐次代理参数，
不能把 CLI 的代理选项直接套在模块上，也不能将 HTTPS_PROXY 的存在当作已生效。
不通过静默启用系统代理、解析显示表格或伪填来源来关闭此门禁。

依据为微软的 [Find-WinGetPackage 公共接口](https://github.com/microsoft/winget-cli/blob/master/src/PowerShell/Help/Microsoft.WinGet.Client/Find-WinGetPackage.md)、
[Source 的 best-effort 实现](https://github.com/microsoft/winget-cli/blob/master/src/PowerShell/Microsoft.WinGet.Client.Engine/Extensions/CatalogPackageExtensions.cs)
及 [CLI 代理选项](https://learn.microsoft.com/en-us/windows/package-manager/winget/)。
以上只界定接口与来源语义，实际网络失败结论来自本轮目标原生日志。

未发布制品，也未将先前 Python/Node/Go/uv 在线成功证据冒充本轮重新安装结果。
