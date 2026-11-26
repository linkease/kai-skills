---
name: kai-tool-bootstrap
description: 查询或准备指定目标上的 Bash、完整 jq、mise 和内部客户端；返回实际路径与校验结果。
owner: system-pack/common
systems: ubuntu, debian, istoreos, openwrt, linux, macos, windows
triggers: 安装 Bash, Git Bash, 完整 jq, 引导工具, 准备 mise, ks-cli 版本
auto-use: suggest
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

Unix `sh scripts/prepare.sh probe|plan|ensure`；原生 Windows `scripts/prepare.ps1 -Action Probe|Plan|Ensure`。`probe`/`plan` 不安装，`ensure` 修改所声明的工具安装范围；首次入口不依赖 Bash/jq/zsetup。单工具入口 `bash scripts/tool.sh probe|plan|ensure TOOL`。

复用兼容且归属明确的安装；无原生发布物、外来修改和校验失败分别返回错误，不覆盖外来文件、不装其他平台程序、不改全局 PATH、不启动服务。WSL 是独立 Linux 环境。准备工具不证明使用它的业务已成功。[平台与依赖](data/platforms.md)、[Windows PKI 范围](resources/windows-pki.md)。
