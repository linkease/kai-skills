---
name: kai-download-acceleration
description: 检查文件、Git、Docker 和开发下载加速，并核对本次网关与校验证据。
owner: system-pack/common
systems: ubuntu, debian, istoreos, openwrt, linux, macos, windows
triggers: 文件下载慢, GitHub 文件, 下载链接, docker pull, Docker 镜像下载, git clone, 下载加速
negative-triggers: 网速慢, 测速, 宽带速度, pip install, npm ci, go mod, uv sync
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

在实际目标使用已有 Bash/jq/ks-cli；缺工具走 kai-tool-bootstrap，服务准备交给目标平台生命周期。Doctor/Explain 仅读，安装成功或内容校验不代表经过加速。

`bash scripts/accelerate.sh` 的小入口：
- `download HTTPS_URL DESTINATION SHA256`：独立可信摘要、已有父目录；临时下载校验后独占激活，保留冲突/链接。默认 auto 且不启动服务；`KAI_DOWNLOAD_MODE=auto|direct|accelerated|race` 选择模式。
- `git-clone HTTPS_REPOSITORY DESTINATION FULL_COMMIT`：公开 GitHub、原生 HTTPS Git>=2.37；仅复用干净受管目录，进程内路由，保留 Host/SNI/TLS，不改 DNS/hosts/全局 Git 或处理私有凭据。
- `docker-pull IMAGE@sha256:DIGEST`：已有授权 daemon 且已有网关 mirror（默认 https://registry.linkease.net:5443，可用 KAI_DOCKER_GATEWAY_MIRROR 指定）；不修改 daemon，验证 RepoDigest。
- `doctor TOOL`、`explain TOOL -- NATIVE_ARGS...`：返回原生计划，不执行下载。

保留原生退出码、摘要、TLS、锁及路由收据；已验证的直连可成功，但不能称加速。SDK/依赖仍由各自技能负责。

需要证明加速才阅读 [证据合同](data/evidence.md)，以实际客户端、同服务实例和时间窗口的网关证据构造 manifest，再用 `bash scripts/evidence.sh MANIFEST CLIENT_LOG GATEWAY_LOG`；缺证据报告 pending，区分直连、源站和缓存命中。

Broad WAN degradation does not prove a gateway helps; compare base and target paths before selecting routing.

结构化链路故障可交 kai-network-quality：保留 operationId、目标和预算，修复后同条件复测，确有改善才重试原动作一次。HTTP认证/404、架构、依赖及校验失败交原软件业务，不泛化为网络问题。iStore 原生集成有证据缺口时才按需读取对应 Docker/域名折叠适配技能。
