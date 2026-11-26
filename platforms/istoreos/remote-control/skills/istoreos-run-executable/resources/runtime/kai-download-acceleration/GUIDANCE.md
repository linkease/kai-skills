---
name: kai-download-acceleration
description: 对明确文件、Git 或 Docker 目标执行有校验的下载操作，或查询现有网关计划与传输证据。
owner: system-pack/common
systems: ubuntu, debian, istoreos, openwrt, linux, macos, windows
triggers: 文件下载慢, GitHub 文件, 下载链接, docker pull, Docker 镜像下载, git clone, 下载加速
negative-triggers: 网速慢, 测速, 宽带速度, pip install, npm ci, go mod, uv sync
auto-use: suggest
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

`bash scripts/accelerate.sh download HTTPS_URL DESTINATION SHA256` 下载独立可信摘要匹配的内容，父目录需已存在；私有候选校验后独占激活，不覆盖冲突或链接。KAI_DOWNLOAD_MODE 默认 direct；auto|accelerated|race 仅在调用者明确选择时使用，不启动网关。

`git-clone HTTPS_REPOSITORY DESTINATION FULL_COMMIT` 处理公开 GitHub、原生 HTTPS Git>=2.37，保留精确 commit 和干净受管目录，进程内路由不改全局配置。`docker-pull IMAGE@sha256:DIGEST` 要求已有授权引擎与已配置的指定 mirror，并验证 RepoDigest；不会配置或启动 daemon。

`doctor TOOL`、`explain TOOL -- NATIVE_ARGS...` 返回现有接口的只读计划，不下载。Bash/jq/ks-cli 等依赖需已存在；查询不安装依赖，失败不自动重试或改变任务。

原生退出码、SHA256、TLS 和策略回执保留。直连校验成功不等于加速成功。[证据合同](data/evidence.md) 定义当前客户端、同一网关实例和时间窗口的字段；`bash scripts/evidence.sh MANIFEST CLIENT_LOG GATEWAY_LOG` 返回相应验证。缺证据为 pending，源站/缓存/客户端直连分别记录。网络原因与是否更改路由由模型结合证据判断，本能力不自动处理整个下载故障。
