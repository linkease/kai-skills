---
name: kai-network-quality
description: 使用 FastNet 测量和诊断 Linux/iStoreOS 的公网、目标下载路径、IPv4/IPv6、NAT 与设备间 LAN 质量，并为软件安装或下载失败提供结构化证据；不修改网络配置。
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources required by its own workflow.

## Local supporting resources

- `kai-tool-bootstrap`: [local instructions](resources/runtime/kai-tool-bootstrap/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

Prepare tools locally with `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`
and its explicit `ensure TOOL` operation when needed. Before Bash exists on Windows,
use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`
through native PowerShell, then the authorized Ensure operation.

## Business workflow
# Kai Network Quality

The machine wrapper requires full jq, Linux `setsid`, and native zsetup capture
(or Linux `timeout`) in addition to a compatible FastNet. Prepare missing tools through the local kai-tool-bootstrap
resource. Each operation first performs a bounded schema-1 capabilities check;
legacy menus and malformed output are incompatibility failures, even on exit 0.
Single-result operations validate their JSON envelope. Native JSONL monitoring
and LAN server streams retain FastNet's progress and cancellation behavior.

Use FastNet as the network evidence and diagnosis owner. Preserve its existing
human menu, commands, and Web UI; this skill uses the additional machine
interface. FastNet observes and assesses. It does not authorize or perform a
network remediation.

## Workflow

1. Run `sh scripts/network.sh inspect`. This is local-only, does not contact an
   external endpoint, and does not run a bandwidth test.
2. Choose the smallest operation:
   - Installation or target download failed: construct a bounded request and run
     `validate`, then `diagnose` for the exact metadata/artifact endpoints.
   - General experience: `measure quick`.
   - WAN capacity: `measure wan` or `measure multi`.
   - NAT or IPv6 only: `measure nat` or `measure ipv6`.
   - Confirmed peer: `measure lan HOST:PORT [PARALLEL]`.
   - Recurring target health: `monitor REQUEST STORE [INTERVAL] [COUNT]`.
   - Authenticated peer session: `lan-serve HOST:PORT TOKEN_FILE [TTL]` on
     the server, then `lan-test HOST:PORT TOKEN_FILE [PARALLEL] [DURATION]`.
3. Before `diagnose` or any `measure`, explain the external endpoints and wait
   for confirmation. WAN, quick, multi, and LAN may saturate the link. Execute
   with `KAIPLUS_CONFIRMED=1` only after confirmation.
4. Report condition and findings first, then evidence and limitations. An
   unhealthy finding means the diagnosis succeeded. It is not a FastNet tool
   failure.
5. A remediation remains with its owner. Repeat the same profile, targets,
   budget and `operationId` afterward. Retry the owning install/download action
   at most once, and only when comparable verification improved.

## Installation handoff

For a bounded diagnosis, start from [the complete request example](data/diagnose-request.example.json).
Put the owning operation ID in **`metadata.operationId`** and the byte limit in
**`budget.maxResponseBytes`**; the time limit is `budget.timeoutSeconds`.
There is no top-level `operationId` or `maxTransferBytes` field. Replace the
example's target and ID with the explicitly authorized values. Never drop the
ID to make validation pass. If the request is rejected, correct its fields
before any external execution; do not reverse-engineer the executable or try
unrelated payloads.

`validate` returns `command: "fastnet agent validate"` without starting network
traffic. This skill's `diagnose` entry calls the supported `agent execute` JSON
interface, so its result uses **`command: "fastnet agent execute"`**. The returned
`result.operationId` must equal the request's `metadata.operationId`. A
successful diagnosis without that correlation does not complete an installation
handoff. Confirmation for this wrapper is **`KAIPLUS_CONFIRMED=1`**.

Read [the installation handoff contract](data/install-handoff.md) before using
FastNet from `kai-software` or `kai-download-acceleration`. Never infer targets
from an unbounded log. Use endpoints from the owning plan or structured native
failure, remove URL credentials, and keep request files mode 0600. Do not put a
token, signed query, LAN token, or complete request body in the response.

DNS, TCP, TLS, transport timeout, advertised-but-broken IPv6, HTTP 429/5xx, and
target-path degradation may justify diagnosis. HTTP 401/403/404, missing
dependencies, unsupported architecture, signature/hash policy, and package
conflicts remain with the software owner unless separate transport evidence
exists.

## Platform and installation boundaries

- Resolve the target's FastNet binary; do not use a controller binary for a
  remote target.
- On iStoreOS, install the packaged FastNet application through `kai-software`.
- On supported ordinary Linux targets, use the source-qualified
  `zsetup:fastnet` candidate through `kai-software` after inspecting and
  confirming its plan. Do not run an ad-hoc curl installer here.
- The currently published FastNet installer does not establish macOS or Windows
  support. Do not invent an installation path for those systems.
- A router-side result does not prove client Wi-Fi quality. Compare a router
  measurement, client measurement, and trusted LAN peer when localization needs
  that distinction.
- Route FastNet Web UI/service lifecycle failures to the target's service and
  log owner. The CLI does not require the Web UI service to run.

## Commands

```sh
sh scripts/network.sh inspect
sh scripts/network.sh validate REQUEST.json
KAIPLUS_CONFIRMED=1 sh scripts/network.sh diagnose REQUEST.json
KAIPLUS_CONFIRMED=1 sh scripts/network.sh measure quick
KAIPLUS_CONFIRMED=1 sh scripts/network.sh monitor REQUEST.json HISTORY.jsonl 5m 12
sh scripts/network.sh history compare --store HISTORY.jsonl --before RUN1 --after RUN2 --json
```

Monitoring performs only bounded target diagnosis, never saturation testing.
FastNet creates history as private JSONL and compares only matching network
context, profile, and targets.

For legacy LAN measurement authentication, pass the token in
`FASTNET_LAN_TOKEN`. Prefer the expiring `lan-serve`/`lan-test` session, whose
token travels in a mode-0600 file and is never printed or placed in argv.
