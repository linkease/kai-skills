# Windows 原生目录及依赖复验批次

用户在上一批三轮停止后明确同意继续。本批重新授权最多三轮，旧记录和失败不覆盖。

## 任务树及验收

1. 冻结程序及目标状态：复用 KSpeeder `f5665424f3af5ce3bd8f1bc07598da2103656154` 的验证构建，上传后核对远端 SHA256/capabilities；记录原有软件、共享 VC++、PATH 和服务状态。
2. Python EXE：固定 3.12.10，单次原生调用保留 MSYS argv，TargetDir 使用规范 Windows 反斜杠。验收要求原包完整性及原生复验、安装、Python/SSL 实际使用、注册版本、卸载和配置保护；参数预演不能替代实际安装。
3. 依赖准备：Neovim 0.11.5 及其声明的 VC++ x64 依赖，全部经过正式 auto 下载、原始摘要与原生导出复验；记录每个包的版本、选路、校验结果，失败不得启动安装。
4. 安装及清理：区分既有依赖复用与新装，保留共享运行库及既有软件；若必须改变共享运行库版本，准备具体已校验制品后再确认。主程序实际运行、注册状态和归属清理必须验证。

失败最多优化复验三轮；超限或产品语义决策停止。无 CONNECT、默认代理、信任/吊销策略或既有 SCM 服务修改。原始诊断、连接配置及设备路径保存在仓库外。

## 原生结果

本批第二轮通过 Python EXE 安装闭环、依赖完整下载及 Neovim 的依赖复用安装闭环，未使用第三轮。上批 PuTTY MSI 成功和 Python 失败均保留，不回写历史结论。机器结果见 [结构化记录](windows-winget-path-retest-20261105-results.json)。

第一轮停在重复的 Bash 准备调用，尚未安装 Python。原机检查发现仅有外层 PowerShell 启动器在 `ReadToEnd()`，没有子进程；核对 PID、解码后启动器代码及无子进程边界后结束该调用。临时网关正常停止。第二轮复用既有已验证 jq/Git Bash 和候选客户端，移除本次 WinGet 不需要的 mise/Bash 再引导，并用本地注册信息检查原有安装；这不是新的全量 bootstrap 验收。

Python 3.12.10：对单次 ks-cli 原生调用保留 MSYS argv，TargetDir 使用规范 Windows 反斜杠；完整元数据/载荷准备、原生复验和实际安装通过。Python/SSL 运行断言精确版本，原生注册查询返回 3.12.10；随后通过原包管理器卸载。原包 SHA256 为 `67b5635e80ea51072b87941312d00ec8927c4db9ba18938f7ad2d27b328b95fb`，本批原生 Authenticode 为 Valid，签名者 Python Software Foundation。上一批的 1606 在该参数修正后不再出现。

依赖下载：Neovim 0.11.5 的固定主包和 Microsoft.VCRedist.2015+.x64 14.51.36247.0 均通过 auto 获取、官方 SHA256 与原生导出复验。主 MSI SHA256 为 `cd43d46dfdf1e02c9c571ace0a757389b1ce5c750d627172dbc76d24d8428a76`，VC++ EXE 为 `843068991daaa1f73ad9f6239bce4d0f6a07a51f18c37ea2a867e9beca71295c`。VC++ 签名为 Valid/Microsoft Corporation；Neovim MSI 为 NotSigned，按原生 WinGet 与官方摘要策略接受，不将其写成签名 MSI 成功，签名 MSI 正向证据仍为上批 PuTTY。

依赖安装：未传 skip-dependencies，正式 ks-cli/WinGet 完成 Neovim 安装；以 headless、无配置/无状态文件模式运行 Lua 断言 v0.11.5，原生注册版本同为 0.11.5，再卸载测试主包。[对应 WinGet 版本](https://raw.githubusercontent.com/microsoft/winget-cli/v1.29.380/src/AppInstallerCLICore/Workflows/DependencyNodeProcessor.cpp)会复用已满足清单的依赖。本机 x64 VC++ 保持 14.36.32532.0，因此本用例通过的是依赖复用；准备回执中的 14.51.36247.0 不是已安装版本。x86 VC++ 亦原已安装，为 14.34.31938.0。缺失依赖首次安装、版本升级及多层图未验证。

以上成功回执的 `catalog_refresh` 仍为 `failed-native-cache-used`，没有把安装成功写成目录刷新修复或 fresh CRL/OCSP 通过。各载荷选路分别记录；原站直连不计为 KSpeeder 加速命中。候选程序仍为 f5665424 构建，不是已发布制品。

## PowerShell Transport 修复

任务树：定位原生输入等待 → 确定性 EOF/截断回归 → 单独提交测试 → 输入结束标记 → 本地及 Windows 原机验证。

验收：完整消息即使输入保持打开也执行；截断消息不得执行；Unicode、param、原生退出码及 pinned host 检查保持；远程超时仍终止所属进程树。

新测试在旧实现产生两个红灯：保持 stdin 打开时等待 EOF，外层返回 255；截断消息却执行了脚本并返回 0。测试先单独提交 `673b8a2`。修复把外层启动器改为读取每次调用唯一的输入结束标记，再写入既有 supervisor 脚本；不变更授权、SSH 主机密钥校验或 Windows Job Object 管理。

三项针对性回归通过。Windows 原机以真实 SSH 保持输入管道打开，脚本正常返回 37、中文及 param 正确；另以四秒 deadline 启动一个先写 started、十秒后写 escaped 的子进程，返回 124，原生检查 started=true、escaped=false，证明实际子进程启动后被清理。不是只以本地 mock 推断 Windows Job Object 行为。相关私有输入保留仓库外。

## 自检、审计与边界

桌面契约 26 项、业务分发 53 项、M3 Transport/M2 canonical 契约全部通过，生成一致和 whitespace 检查通过。本轮 Go 契约在已验证 SSD wrapper 中执行。新增 skill 说明区分 prepared packages、实际注册版本、依赖复用和首次安装。

最终独立原生审计：测试 Python/PuTTY/Neovim 无注册安装；共享 x64/x86 VC++ 版本保持，用户及系统 PATH 保持，原有服务状态/启动模式/参数及二进制 SHA256 保持，临时程序及端口清理。执行下一用例期间的一份中间审计不作为最终清理通过证据，原文件另存保留。SDK、下载缓存及日志仅留在明确归属目录。

本批关闭此前的 Python 安装目录阻塞和依赖载荷下载阻塞，并验证依赖复用。BM8 的全量集合、SCM 生命周期、缺失依赖新装/升级、fresh CRL/OCSP 及目录刷新仍未验收；其他系统失败不因此关闭。当前不是同一最终发行物的完整 110 条证据，BM9 release-ready=false，BM10 未发布。
