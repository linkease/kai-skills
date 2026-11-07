---
name: istoreos-systools
description: 诊断和修复 iStoreOS 的 IPv6 模式、硬盘休眠、应用商店及升级后内核模块问题；只通过设备自带系统工具的受控入口执行，不负责网络测速。
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources required by its own workflow.
# iStoreOS System Tools

Use this skill for the supported system-maintenance cases above. Do not invoke arbitrary files under `/usr/share/systools`; the official `/usr/libexec/systools.sh` dispatcher accepts more actions than KaiPlus has reviewed.

## Workflow

1. Run `scripts/inspect.sh <network|storage|store|upgrade|all>` and summarize the evidence in user language.
2. Say whether the proposed next step only checks the device or changes it.
3. For a change, state the affected subsystem, likely interruption, backup or rollback path, and verification command. Wait for explicit user confirmation.
4. Only after confirmation, run `KAIPLUS_CONFIRMED=1 scripts/apply.sh <action> [argument]`.
5. Re-run the matching inspection and report success or the remaining problem.

Network measurement belongs to `kai-network-quality`. IPv6 actions here change network and firewall configuration and may interrupt access. Store repair and incompatible-kernel-module repair reinstall packages and require a configuration backup first.

## Reviewed Actions

- `ipv6_pd`, `ipv6_relay`, `ipv6_nat`, `ipv6_half`, `ipv6_off`
- `istore-reinstall`
- `reinstall_incompatible_kmods`

If the official dispatcher or requested action is unavailable, stop and explain the missing component. Never substitute a similarly named source-tree script or invent an action.
