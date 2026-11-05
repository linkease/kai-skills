# macOS Homebrew GHCR 专项

用户授权继续检查 macOS，重点为 `brew install` 的 GHCR 加速。本批最多三轮优化，历史失败保留，不借用其他服务的登录凭据。

## 任务树与验收标准

1. 固定候选程序、系统及已有 Homebrew 软件/服务基线；通过独立归属目录和临时前台网关复现 manifest/blob 失败，保存首处网关错误及最终 Homebrew 错误。
2. 区分 Homebrew 签名 API、OCI manifest/blob、registry 授权、上游路由和 DNS；以单变量对照确认原因，不能用 API 或本地健康通过代替 bottle 成功。
3. 按现有产品语义修复客户端或 skill 指引；代码缺陷先增加失败回归并单独提交测试，再修实现。若需要改变授权语义或部署未授权上游则停止相关动作并说明。
4. 在原生 macOS 实际执行正式客户端/业务 skill 的 bottle 安装、程序使用和归属清理，保留 Homebrew 原始完整性检查，明确直连与加速命中。
5. 自检生成及相关契约，确认既有服务、应用、代理、DNS、信任和用户配置保持。未完成的验收继续标为未验证。

原始诊断及设备连接信息保存在仓库外。

## 结果

已定位当前失败为既有 GHCR Plus 权限门控，API 加速通过，真实 bottle 安装尚未通过。结构化证据见 [本批机器记录](macos-brew-ghcr-20261105-results.json)。未修改客户端或服务端程序实现，也未更改免费/Plus 边界。

## 第一轮原生结果

原机 Homebrew 为 `6.0.16`。最初的准备检查在隔离缓存中执行 `brew list`，该命令触发 API 下载并超时，尚未启动测试网关；原始捕获保留。准备改为只读 Cellar 目录清单。最终审计另纠正了非交互 PATH 下的 brew 绝对路径，保留首次失败记录。这些是测试准备问题，不计为 GHCR 修复成功。

本轮客户端及网关均为 `f5665424f3af5ce3bd8f1bc07598da2103656154` 的验证构建，以远端 SHA256 和运行时 capabilities 确认。原 harness 的 gateway 源码标签残留旧常量，不以该标签作来源结论。测试没有使用公开发布制品或替换既有服务。

`kai-software` 独立封装实际执行 required 策略、显式 GHCR artifact 域名。签名 API 经 `dl-homebrew-api` 返回 200，原生 skill info 查询成功，tree 候选为 2.3.2；这不代表 bottle 下载成功。

Homebrew 6 的 OCI 请求已抵达本地网关：两次 `/v2/homebrew/core/tree/manifests/2.3.2` 和一次对应 SHA256 blob 请求均为 403。响应正文 SHA256 均为 `d8a4c2563dac26811c11c8ad0bc6edfd8fa106a5623e600f25102fda12be4101`，与当前 `cmd/multi/unanthorized_handlers.go` 的 Plus 拒绝正文逐字节一致。根路径 `/v2/` 也得到相同 403。因此 Host/TLS/本地解析及 OCI 路径已到达正确入口，当前失败发生在 Plus 检查处，没有进入获授权后的 manifest/blob 传输验收。

实际安装在 300 秒 Transport deadline 返回 124。skill 等待原生命令结束才生成最终回执，超时捕获没有最终原生 fallback 错误，不能把它写成已确认的 DNS 错误。另一次独立直连 `https://ghcr.io/v2/` 探测为 curl 28/超时，并非此前批次的 curl 6/DNS 失败；独立探测不能代替安装内部 fallback 的错误证据。

## 现有能力与下一步

现有 `brew-env --mode free` 只输出 API 域名；`--mode plus` 增加 `HOMEBREW_ARTIFACT_DOMAIN=https://ghcr.linkease.net:PORT`，原机输出已核对。`cmd/multi/proxy_handlers.go` 对该域名先检查 `CanUseFastChannel()`，要求已登录及 Plus，再分发到 GHCR registry handler。现有产品设计已明确 bottle 大文件走此权限路径，不能用通用 `/homebrew-bottles` DomainFold 绕过。

Homebrew [正式环境契约](https://docs.brew.sh/Manpage#environment)支持 ARTIFACT_DOMAIN 改写 bottle 的 registry 域名，并保留原始包校验。这里的实现方向可以支持 GHCR；当前结果只证明正确到达权限门控，没有证明授权后的实际安装已通过。

下一步验收任务树：正常授权的 Plus 测试会话 → 同一网关 `/v2/` 返回 200 → 正式 Homebrew manifest/blob 传输及原始摘要 → `brew install` → 程序实际使用和注册版本 → 只卸载测试归属软件 → Cellar/代理/服务清理审计。根路径 200、API 成功或本地 handler mock 测试均不能替代完整传输。已向用户询问可用测试会话；本批没有登录、复制其他服务凭据、部署上游或改变权限规则。

本轮没有因为同一权限前置重复执行第二、三轮安装。最多三轮限制保留，实际后续安装需要先具备正常授权的测试会话。其他 macOS Git upload-pack 405、集合和服务生命周期仍未关闭。

## 自检

当前 checkout 的 2 项 TLS GHCR 分发/权限回归、5 项 Homebrew 客户端路由回归及 8 项独立包契约通过，无跳过；生成一致性通过。它们验证本地契约，不表示真实上游已验证。skill 已补充 API doctor 与 GHCR 就绪的区别、独立权限探测及错误保留，生成内容从源码重建。

最终原机 Cellar、代理和测试端口基线与前置一致，测试 tree 未安装，临时网关已停止。没有执行 hosts/DNS、代理或信任配置修改。原始连接、设备路径和日志留在仓库外。BM9 release-ready=false，BM10 未发布。
