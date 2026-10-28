---
name: istoreos-systools
description: 诊断和修复 iStoreOS 的 IPv6 模式、硬盘休眠、应用商店及升级后内核模块问题；只通过设备自带系统工具的受控入口执行，不负责网络测速。
owner: system-pack/istoreos
systems: istoreos
triggers: IPv6 模式, IPv6 PD, IPv6 relay, IPv6 NAT, 硬盘不休眠, 硬盘唤醒, 应用商店损坏, iStore 修复, 升级后异常, 内核模块不兼容
negative-triggers: 网络测速, 网速慢, NAT 类型, 局域网测速, 普通软件安装, Docker 镜像下载, overlay 空间不足
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: low
---

# iStoreOS System Tools

Use this skill for the supported system-maintenance cases above. Do not invoke arbitrary files under `/usr/share/systools`; the official `/usr/libexec/systools.sh` dispatcher accepts more actions than KaiPlus has reviewed.

## Workflow

1. Run `scripts/inspect.sh <network|storage|store|upgrade|all>` and summarize the evidence in user language.
2. Say whether the proposed next step only checks the device or changes it.
3. For a change, state the affected subsystem, likely interruption, backup or rollback path, and verification command. Wait for explicit user confirmation.
4. Only after confirmation, run `KAIPLUS_CONFIRMED=1 scripts/apply.sh <action> [argument]`.
5. Re-run the matching inspection and report success or the remaining problem.

Network measurement belongs to `istoreos-network-quality`. IPv6 actions here change network and firewall configuration and may interrupt access. Store repair and incompatible-kernel-module repair reinstall packages and require a configuration backup first.

## Reviewed Actions

- `ipv6_pd`, `ipv6_relay`, `ipv6_nat`, `ipv6_half`, `ipv6_off`
- `istore-reinstall`
- `reinstall_incompatible_kmods`

If the official dispatcher or requested action is unavailable, stop and explain the missing component. Never substitute a similarly named source-tree script or invent an action.
