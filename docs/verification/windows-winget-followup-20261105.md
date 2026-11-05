# Windows WinGet 原生安装复验

用户在上一批三轮停止后明确授权继续解决 Windows 安装和依赖问题。本批最多三轮，保留各轮结果；旧原生失败和 MSZIP 离线成功记录不覆盖。

## 任务树及验收标准

1. 冻结当前源码、程序摘要、原生 WinGet/模块、既有安装和服务状态。验收：远端程序摘要与冻结清单相同，任务目录归属明确，既有服务保留。
2. 通过 `kai-software` 正式入口安装 PuTTY 固定版本。验收：线上压缩元数据通过源摘要检查和解析，原始安装器经 auto 下载及完整性检查，原生安装成功，查询注册版本并实际运行，卸载本轮新增软件。
3. 验证签名 EXE 和具有明确包依赖的安装。验收：主包及全部选中依赖先完成准备和原生验证；顺序及结果可追溯，失败不启动后续安装，不把已存在依赖写成新装成功。
4. 清理及审计。验收：临时程序和端口回收、原服务保持、既有软件不卸载；直连与加速分开记录，不修改 CONNECT、默认代理、信任或吊销策略。

实现后自检；原生业务失败最多修复复验三轮，超限或产品语义决策停止。私有目标配置、路径、诊断和原始回执放在仓库外。

## 基线

KSpeeder 源码 `f5665424f3af5ce3bd8f1bc07598da2103656154`；复用上一批该提交的 Windows 冻结程序，上传后在目标核验 SHA256，再通过 capabilities 确认当前候选。skills 基线 `cc8f1c56fb696395f8749daba442d3aa82844685`。复用已在任务目录准备的官方 WinGet 模块，不全局安装模块或更新既有 SCM 服务。

## 已完成的原生结果

PuTTY 0.85.0.0 MSI 第一轮通过：从原生目录查询固定版本、线上 MSZIP 和 manifest 的源摘要校验与解析、auto 原始安装器下载、原生导出复验及安装、`plink -V` 实际运行、卸载本轮新增安装、网关控制会话停止均成功。导出的 MSI 原生 Authenticode 为 Valid，签名者 Simon Tatham，SHA256 为 `2213ebacf962b709411d654a40087508a694756bc4e41c5a1c24ad86596b2511`。元数据及安装器均选择 origin，本用例证明正式路径可用，不宣称加速命中；原生目录刷新/CRL 的独立门禁不由此关闭。

Python EXE 第一轮在新网关就绪阶段失败，没有执行安装；清理会话等待未正常结束，随后独立审计确认任务端口和程序均不存在，既有服务保持。第二轮在启动前置中改用 .NET 查询监听端口并增加控制阶段标记，网关就绪后继续。一次成功不足以唯一归因第一轮超时，保留该基础设施失败，未修改产品代理、签名或源策略。

依赖用例选定 Neovim 0.11.5，其[官方安装清单](https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests/n/Neovim/Neovim/0.11.5/Neovim.Neovim.installer.yaml)声明依赖 Microsoft.VCRedist.2015+.x64。目标已有 VC++ 14.36.32532.0，目录当前提供 14.51.36247.0；先执行完整主包及依赖下载/原生复验，保留共享运行库，不把下载成功写成依赖新装成功。

## 三轮停止及自检

Python 第二轮自动获取了固定 EXE，SHA256 为 `67b5635e80ea51072b87941312d00ec8927c4db9ba18938f7ad2d27b328b95fb`，原生两次报告 installer hash verified，Authenticode 为 Valid，签名者 Python Software Foundation。安装器随后等待且日志为空。检查实际 setup 进程命令行，发现 `/quiet` 未保留、已变为 Git 路径；只读 `ks-cli --json --explain winget` 对照也复现 normalPreserved=false。对单次调用设置 `MSYS2_ARG_CONV_EXCL='*'` 后 fixedPreserved=true。该错误属于本轮自定义 Bash 测试调用，不是正式 PowerShell helper 丢参。

已校验任务归属及客户端路径后取消该次 ks-cli 的四个所属进程，网关控制会话正常结束。没有通过 GUI 点击安装，也没有改为关闭签名/吊销检查。

Python 第三轮保留了原生静默参数，完成压缩元数据、载荷准备及原生导出复验，最终安装返回 `WINGET_NATIVE_INSTALL_FAILED`；WinGet 记录 installer exit 1603，Python Burn 为 `0x80070643`，内部 core MSI 在 `CostFinalize` 阶段记录 Error 1606。不能把它继续归为 MSZIP、下载或证书失败。错误位置与传入的正斜杠 TargetDir 对照另有只读回执；测试脚本已准备使用规范 Windows 反斜杠路径，参数预演通过，但没有第四轮安装，因此目录修正仍待原生验证。

本批依赖下载/安装没有执行；只完成官方清单、既有运行库及 Neovim 未安装的检查，不记为通过。后续如确需升级共享 VC++，应先完整准备和验证载荷，再明确处理已有共享运行库的保留策略，不能因为测试方便先卸载旧库。

收尾独立原生审计：PuTTY、Python 3.12、Neovim 均未注册安装；共享 VC++ 仍为 14.36.32532.0；用户 PATH、系统 PATH、既有服务状态/启动模式/路径与本批前一致；任务程序和端口均不存在。第三轮失败的 Python 安装已回滚，没有遗留已注册的 Python 包。SDK、下载缓存及日志保留在明确归属目录供复核。

本轮 skill 更新限于已复现的原生参数与安装目录边界；实际 argv 红绿对照、skill 校验、独立包/集合锁/预设生成一致性和 whitespace 检查作为本地自检。按用户三轮上限停止安装复试。MSI 闭环已通过，EXE 及依赖闭环未通过，BM9/BM10 保持未放行。结构化结果见 [机器记录](windows-winget-followup-20261105-results.json)。
