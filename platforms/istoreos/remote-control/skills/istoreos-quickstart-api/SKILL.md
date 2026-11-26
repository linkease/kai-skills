---
name: istoreos-quickstart-api
description: Send one explicitly selected QuickStart API request through a bound LuCI transport; return its actual response envelope.
metadata:
  opencode/autoinvoke: "false"
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.

## Local supporting resources

- `luci-http-controller`: [local instructions](resources/runtime/luci-http-controller/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

## Operation interfaces
`sh scripts/request.sh GET PATH` queries the selected endpoint. `TARGET_HTTP_WRITE_APPROVED=YES sh scripts/request.sh POST PATH JSON` sends one selected write. [API reference](data/api-summary.md) describes endpoint schemas; it does not choose a repair or sequence.

Transport owns credentials and binding. Existing executor authorization must cover the exact target, method, endpoint and body; dangerous endpoints also require QUICKSTART_DANGER_APPROVED=YES. These markers grant no host permission. Native success is checked; request acceptance is not an application postcondition. No init file is rewritten. Passwords do not belong in arguments, model context or returned evidence.
