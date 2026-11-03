---
name: macos-launchd-logs
description: Inspect one macOS launchd job and bounded unified logs, prepare a change plan, apply an explicitly approved kickstart or stop, and verify the resulting job state.
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources required by its own workflow.
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
