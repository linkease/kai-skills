---
name: kai-network-quality
description: 使用 FastNet 测量和诊断 Linux/iStoreOS 的公网、目标下载路径、IPv4/IPv6、NAT 与设备间 LAN 质量，并为软件安装或下载失败提供结构化证据；不修改网络配置。
owner: system-pack/linux
systems: ubuntu, debian, istoreos, openwrt, linux
triggers: 网速慢, 测速, 宽带速度, 上行速度, 下行速度, 延迟, 抖动, NAT 类型, IPv6 测试, IPv6 可用性, 局域网测速, LAN 测速, FastNet, 安装网络诊断, DNS 超时, TLS 超时
negative-triggers: 修改 IPv6 模式, 修改网络配置, 只安装软件, Docker 镜像下载慢, 认证失败, 软件包冲突
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

FastNet 是网络观察与诊断的维护源，不改网络配置。使用目标的程序；Linux/iStoreOS 需兼容 FastNet/full jq/setsid 和 zsetup capture 或 timeout。缺工具走 kai-tool-bootstrap；iStore 用原生包，普通受支持 Linux 用 kai-software 的 zsetup:fastnet；不推断 Windows/macOS 安装支持。

先 `sh scripts/network.sh inspect`，仅本地能力检查，不外联。按问题选最小操作：`measure quick|wan|multi|nat|ipv6`；已确认对端用 `measure lan HOST:PORT [PARALLEL]`。外部诊断/测量前说明目标并在现有授权内取得确认，执行时 `KAIPLUS_CONFIRMED=1`；带宽测试可能占满链路。

安装/下载的链路故障使用 [请求示例](data/diagnose-request.example.json) 和 [交接合同](data/install-handoff.md)：先 `validate REQUEST.json`，再 `diagnose REQUEST.json`。operationId 位于 metadata.operationId，字节/时间上限位于 budget.maxResponseBytes/timeoutSeconds；结果 operationId 必须对应。只使用原计划或结构化失败的已授权端点，去凭据，私有请求文件不回传全文。

不健康 finding 表示诊断完成，不等于工具失败。HTTP401/403/404、包冲突和完整性失败仍归软件业务。修复由原业务负责；复测保留同一 profile/目标/预算/operationId，改善后原动作最多重试一次。路由侧测量不能证明终端 Wi-Fi；需要时对比路由、终端与可信 LAN 对端。

持续观察用 `monitor REQUEST STORE [INTERVAL] [COUNT]`，只做有界目标诊断，不做持续饱和测试；`history compare --store STORE --before RUN1 --after RUN2 --json` 只比较相同环境。认证 LAN 用 `lan-serve HOST:PORT TOKEN_FILE [TTL]` / `lan-test HOST:PORT TOKEN_FILE [PARALLEL] [DURATION]`，令牌放0600文件，不进 argv/答复。保留原生流、退出码和取消；Web/service 故障交服务日志业务。
