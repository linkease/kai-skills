---
name: istoreos-quickstart-api
description: Inspect or change iStoreOS QuickStart functions through their LuCI API when an HTTP target controller is available; endpoint selection and dangerous-operation policy stay in this system skill.
owner: system-pack/istoreos
systems: istoreos
requires: target.http
invocation: manual
auto-use: off
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

# iStoreOS QuickStart API

Use this helper when another iStoreOS skill needs QuickStart status or a user explicitly requests a QuickStart-backed operation. It owns endpoint semantics; `$luci-http-controller` owns authentication and HTTP transport.

Read `data/api-summary.md` only for the relevant endpoint family. Start with GET. Before POST, show the endpoint, body, expected effect, verification GET, and rollback if available. Reboot, poweroff, password, network, Wi-Fi, disk, RAID, package, share, or data deletion also requires `QUICKSTART_DANGER_APPROVED=YES` immediately before execution.

Run the deterministic wrapper from the control environment:

```sh
sh scripts/request.sh GET /system/status/
TARGET_HTTP_WRITE_APPROVED=YES sh scripts/request.sh POST /system/auto-check-update/ '{"enable":true}'
```

The wrapper resolves the sibling transport skill from `SKILLS_DIR`, checks the QuickStart response envelope, and fails when `success` is non-zero. Never put the LuCI password in arguments or files.
