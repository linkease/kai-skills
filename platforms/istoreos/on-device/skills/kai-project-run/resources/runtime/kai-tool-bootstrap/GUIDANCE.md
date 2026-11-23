---
name: kai-tool-bootstrap
description: 准备 Bash、完整 jq、mise 和内部客户端，缺少校验过的原生发布物时明确报告。
owner: system-pack/common
systems: ubuntu, debian, istoreos, openwrt, linux, macos, windows
triggers: 安装 Bash, Git Bash, 完整 jq, 引导工具, 准备 mise, ks-cli 版本
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

先探测，再准备缺项。KAIPlus 可调用 `tool:software_runtime_probe`；确需准备且已有授权时调用 `tool:software_runtime_prepare`。结果给出 Bash、完整 jq 和原生 zsetup 的实际路径；后续调用继续使用这些路径。

独立或远程场景在实际目标执行：Unix `sh scripts/prepare.sh probe|plan|ensure`；Windows 原生 PowerShell `scripts/prepare.ps1 -Action Probe|Plan|Ensure`。首次入口不依赖 Bash/jq/zsetup；Probe/Plan 不安装。WSL 属于另一 Linux 目标。

运行时入口组合现有维护方，验证 jq 的正则/JSON/Unicode 和工具归属。复用兼容安装；外来、修改、无原生发布物或校验失败时按结构化结果停下，不覆盖或替换为其他平台程序。不改全局 PATH、不启动服务、不以直连成功宣称加速。

仅需某个工具时保留 `bash scripts/tool.sh probe|plan|ensure TOOL`。mise/内部客户端、原生 Windows 缓存和证书问题按需读 [平台说明](data/platforms.md) 或 [Windows PKI](resources/windows-pki.md)；不要预读所有平台规则。准备完成与业务验证分别报告。
