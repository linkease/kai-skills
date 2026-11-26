---
name: istoreos-quickstart-api
description: Send one explicitly selected QuickStart API request through a bound LuCI transport; return its actual response envelope.
owner: system-pack/istoreos
systems: istoreos
requires: target.http
invocation: manual
auto-use: off
needs-fresh-data: true
cost: medium
resource-discovery: explicit
---

`sh scripts/request.sh GET PATH` queries the selected endpoint. `TARGET_HTTP_WRITE_APPROVED=YES sh scripts/request.sh POST PATH JSON` sends one selected write. [API reference](data/api-summary.md) describes endpoint schemas; it does not choose a repair or sequence.

Transport owns credentials and binding. Existing executor authorization must cover the exact target, method, endpoint and body; dangerous endpoints also require QUICKSTART_DANGER_APPROVED=YES. These markers grant no host permission. Native success is checked; request acceptance is not an application postcondition. No init file is rewritten. Passwords do not belong in arguments, model context or returned evidence.
