---
name: macos-launchd-logs
description: Inspect one macOS launchd job and bounded unified logs, prepare a change plan, apply an explicitly approved kickstart or stop, and verify the resulting job state.
owner: system-pack/macos
systems: macos
requires: target-shell:posix
triggers: launchd 服务失败, LaunchAgent, LaunchDaemon, macOS 服务未运行, macOS 日志, 重启 Mac 服务
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
---

# macOS launchd and unified logs

Use the four-phase contract with an exact launchd domain and label:

```sh
sh scripts/inspect.sh system com.example.worker
sh scripts/plan.sh system com.example.worker kickstart
TARGET_CHANGE_APPROVED=YES sh scripts/apply.sh system com.example.worker kickstart
sh scripts/verify.sh system com.example.worker running
```

Allowed domains are `system` and `gui/<uid>`. `inspect` and `plan` are read-only. Before `apply`, show the bound Target ID, target domain/label, exact action, disruption, verification, and rollback. Approval must be fresh and scoped to that target and action; the environment guard is not a substitute for the Agent host's approval lease.

This workflow never loads/unloads plist files, changes KeepAlive or permissions, edits preferences, or deletes data. If verification fails, report bounded current evidence and do not loop kickstarts.
