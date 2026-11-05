# macOS 使用既有 Plus 网关验证 Homebrew

用户明确指定检查 Linux 测试主机的既有 Plus 登录状态并用于测试。本批只读取登录和会员布尔状态，使用原有服务，不读取或复制 Token。此前 [未登录临时网关的 403](macos-brew-ghcr-20261105.md) 保留为历史结果。

## 任务树与验收标准

1. 只读核对既有服务的版本、登录/Plus 状态和 GHCR gate；确认当前客户端所需能力齐备。
2. 建立归属明确、只绑定回环地址的临时 SSH 通道，将 Mac 的本地 TLS/admin 端口连接到既有 Linux 服务；保持 alias、Host/SNI 和原生 TLS 校验，不复制登录状态、不替换或重启服务。
3. 在原生 macOS 使用独立 `kai-software` 安装未预装的固定候选，验证 bottle、程序使用、注册版本与卸载。
4. 核对原包摘要，并在全新缓存和禁止 artifact fallback 的条件下补做下载检查；核对两端基线并清理通道。最多三组执行，失败不覆盖历史记录。

## 实测结果

既有 Linux 网关为 `0.7.16`，源码标识 `3aca8b58d228c5e94f6d482bdf841c600fe6b0eb`；API 返回 `is_login=true`、`is_plus=true`，GHCR `/v2/` 为 200。它包含 `download-gateway.v1` 和 `route.homebrew-api.v1`，满足此次客户端的能力要求。Mac 使用 Homebrew `6.0.16`，客户端为 `f5665424` 的验证构建。该网关与此前上传到 Mac 的候选网关是不同程序；本批未在 Mac 启动 KSpeeder。

第一组：正式安装成功，回执已确认 tree 2.3.2 安装；测试脚本误以为通用软件安装回执包含 `status` 字段，未进入程序使用验证即清理。原始失败记录保留。

第二组：修正测试断言后，`kai-software` required 策略成功安装 tree 2.3.2，原生命令输出 bottle manifest/下载成功并 pour `arm64_tahoe` bottle。实际运行 `tree --version` 及目录扫描，返回精确版本且找到任务内文件；原生 info 的 installedVersion 同为 2.3.2，随后通过原管理器卸载。此前未安装 tree，前后 Cellar 清单、代理和测试端口基线一致。

第三组：全新缓存中显式设置 `HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK=1`，正式客户端的 bottle fetch 返回 0，并输出 checksum 验证成功。测试额外断言 verbose 输出必须含域名，但该原生版本的输出不提供此信息，故后置断言失败；没有执行第四组。独立检查已有成功回执、缓存制品以及原机 `resource.rb`/`curl_download_strategy.rb` 中禁止 fallback 的实际实现，区分原生命令成功与测试输出断言失败。

最终 bottle 为 66,262 字节，SHA256 为 `d1967d2ed08717f963addb249ea6b8ca11c26ecb59efba34f2860853a06bedc7`，与原生 OCI manifest 对 `2.3.2.arm64_tahoe` 声明的摘要及大小相同；第二、三组缓存中的包摘要一致。manifest 本身 SHA256 为 `cee62fd18164d7c6120f8fdebfa8c6dced5c9c248343baab1d0baf5010264251`。原生严格下载合同和显式配置支持本次既有 Plus 通道结论；未取得该旧版服务的逐请求 observation 日志，不补造 HTTP 字节级路径证据，也未测量相对直连的速度收益。

## 清理与范围

两端 SSH 通道均已退出，Mac 的测试端口恢复空闲，tree 未保留安装；Cellar 和代理基线保持。Linux 服务 PID、可执行路径、版本及登录/Plus 状态与前置一致；安装后采集的二进制摘要在最终审计中保持，不扩大为未采集的安装前哈希对照。没有调用登录、注销、设置 Token、服务升级或重启。

本批通过的是当前 Mac 客户端与既有 Linux Plus 网关组合下的 tree bottle 安装、实际使用和卸载。它关闭此前该用例缺少授权测试会话的阻塞，不表示所有 formula/cask 或候选网关自身已通过。macOS Git upload-pack 405、业务/系统集合及最终发行候选仍待验证；BM9 release-ready=false，BM10 未发布。

结构化结果见 [机器记录](macos-brew-plus-20261105-results.json)。连接信息、原始日志和任务目录均留在仓库外。
