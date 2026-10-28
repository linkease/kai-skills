---
name: istoreos-network-quality
description: 使用 iStoreOS 内置 FastNet 测量并解释外网带宽、延迟与抖动、NAT 类型、IPv6 可用性和局域网吞吐；用于网速慢、测速、NAT/IPv6 检测和 LAN 测速，不用于特定下载源加速或修改网络配置。
owner: system-pack/istoreos
systems: istoreos
triggers: 网速慢, 测速, 宽带速度, 上行速度, 下行速度, 延迟, 抖动, NAT 类型, IPv6 测试, IPv6 可用性, 局域网测速, LAN 测速, FastNet
negative-triggers: Docker 镜像下载慢, GitHub 下载慢, 文件下载失败, 修改 IPv6 模式, 修改网络配置
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
---

# iStoreOS Network Quality

Use this skill to measure network quality with the device's packaged `/usr/sbin/FastNet` binary and explain the result. Keep measurement separate from configuration changes.

## Workflow

1. Run `scripts/inspect.sh` first. It checks the network and FastNet installation without starting a speed test or exposing the configured API token.
2. Choose the smallest test that answers the user's question:
   - General network experience: `quick` (latency, jitter, download, upload, NAT and IPv6).
   - WAN bandwidth or a selected SpeedTest server: `wan [numeric-server-id]`.
   - Multi-source upload/download throughput: `multi`.
   - NAT classification only: `nat`.
   - IPv6 reachability/readiness only: `ipv6`.
   - Trusted LAN endpoint: `lan <host:port> [parallel]`.
3. Before any test, explain that FastNet contacts external or user-specified endpoints. For `quick`, `wan`, `multi`, and `lan`, explicitly warn that the test can saturate the link. Wait for confirmation, then run `KAIPLUS_CONFIRMED=1 scripts/run.sh ...`.
4. Report the user-level conclusion first, followed by measured values and limitations. A router-side test alone does not prove whether a client Wi-Fi problem exists; compare router results with a client test when that distinction matters.

## Boundaries

- If FastNet is absent, route installation of `app-meta-fastnet` through `kai-software`; do not download an ad-hoc binary. Installing packages requires user confirmation.
- The FastNet CLI does not require `/etc/init.d/fastnet` to be running. Do not start or restart the Web UI service solely to run a CLI test.
- Route FastNet Web UI/service failures to `istoreos-service-manager` plus `istoreos-logs-and-diagnostics`.
- Route IPv6 PD/relay/NAT mode changes to `istoreos-systools`; this skill only measures IPv6 behavior.
- Route a slow Docker image, Git clone, package artifact, or specific URL to `kai-download-acceleration`; a bandwidth test does not repair a download path.
- Use `FastNet speedtest_one --json` for WAN SpeedTest results. Do not treat `/api/speedtest` as authoritative while the packaged API describes it as a placeholder with no upload result.
- Never print `/etc/config/fastnet` wholesale, place its token in a URL, or repeat a LAN test token in the response. Only test a LAN endpoint supplied or confirmed by the user.

## Commands

Locate the installed skill without relying on the current directory:

```sh
SKILLS_DIR="${KAIPLUS_SKILLS_DIR:-${KAIPLUS_HOME:?KAIPLUS_HOME is required}/config/skills}"
sh "$SKILLS_DIR/istoreos-network-quality/scripts/inspect.sh"
KAIPLUS_CONFIRMED=1 sh "$SKILLS_DIR/istoreos-network-quality/scripts/run.sh" quick
```

For an authenticated LAN target, pass the token through `FASTNET_LAN_TOKEN` and do not echo it. `parallel` is restricted to 1 through 13.
