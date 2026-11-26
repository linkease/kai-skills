# Scoped iStore runtime task entrypoints

Historical implementation/test notes. The current Agent/skill/host responsibility and optional discovery contract is [KA0–KA10](agent-capability-milestones-20261126.md); older routing descriptions below are not runtime policy.

## Goal and boundaries

Make iStoreOS runtime and dependency operations correct through skill-owned scripts, without changing Kai's general command executor, ordinary Linux/Ubuntu behavior, global HOME/PATH, client configuration or system Python packages. Extra system-shell observations are permitted; conclusions about mise SDKs and downloads must use the selected SDK and scoped verification results. Arbitrary commands outside these entrypoints are not intercepted.

Canonical ownership: `components/system-packs/istoreos/skills`. Generate both iStoreOS presets with `tools/generate-platforms.sh`; do not edit copies. Keep gateway/CLI binaries and plugin code unchanged for this task.

## Task tree and acceptance

| Task | Delivery | Acceptance |
| --- | --- | --- |
| T1 contracts | Public-script regression tests, separate test commit | Reproduce a wrong HOME/shims boundary, SDK selection failure and missing gateway evidence before implementation |
| T2 probe | environment.sh, exec.sh boundary, probe.sh | Each call establishes and checks integration; exact SDK provenance/version; missing SDK never auto-installs; explicit mise/Agent XDG state preserved; reject Ubuntu misuse |
| T3 operations/results | install receipt, smoke runtime/client/gateway receipts, optional current-log mode, JSON evidence | Keep native verification and isolated real dependencies; preserve exit codes; client-only success is partial; only current matching metadata/artifacts confirm gateway success |
| T4 discovery/consumers | Correct skill/reference/router wording, compact iStore resident routing reminder, generated presets, release gate | System check never claims to enter mise-exec; generated/catalog/budget/OpenCode/Reasonix checks pass; no unrelated OS or Kai executor changes |
| T5 device/Agent | Authorized test-device deployment and fresh execution report | Repeated probes, installed-runtime verification, isolated pip/npm/Go downloads and execution, scoped evidence, natural-language Kai task, unchanged baseline configuration and service health |

Implementation is followed by a full self-check. Optimize against demonstrated failures at most three times, then stop and report any remaining failure. Test fixture construction and initial implementation are not claims of completed device acceptance. Historical tests remain historical; record exact new commands/results and uncovered systems in a separate verification report.

## Result contract

All JSON receipts include schemaVersion=1, operation, status and numeric exitCode. Additional fields describe the operation's scope; a passed runtime-install/probe is not dependency or gateway proof. probe stdout is one JSON receipt; install prints normal logs then a final JSON receipt. A pre-entry/usage error may have only a diagnostic and nonzero exit code.

smoke writes runtime.json and result.json to a new isolated directory. Default mode succeeds with status=partial after runtime and client validation, leaving gateway_validation=pending. Optional gateway-log mode confirms only appended current-window entries after validating the original prefix remains unchanged. Failure keeps separate client/gateway verdicts and returns the appropriate nonzero code. evidence.sh --json supplies a separate gateway verdict when logging is collected externally.

Receipts are execution evidence, not a security boundary against arbitrary shell commands or forged files. Custom dependency operations need their own application tests. Do not create a global command interception policy to compensate for missing evidence.
