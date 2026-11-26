---
name: kai-project-run
description: Plan or execute an explicitly selected Node, Python or Go project transaction with exact SDK, source hashes, locks and expected output.
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.

## Local supporting resources

- `istoreos-app-diagnostics`: [local instructions](resources/runtime/istoreos-app-diagnostics/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `istoreos-app-search`: [local instructions](resources/runtime/istoreos-app-search/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-dev-environment`: [local instructions](resources/runtime/kai-dev-environment/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-project-dependencies`: [local instructions](resources/runtime/kai-project-dependencies/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-software`: [local instructions](resources/runtime/kai-software/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-tool-bootstrap`: [local instructions](resources/runtime/kai-tool-bootstrap/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

Optional tool preparation: `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`
or the separately authorized `ensure TOOL` operation. The native Windows preparation interface is
use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`
through existing native PowerShell. Querying this skill does not install missing tools.

SDK helpers are local at `resources/runtime/kai-dev-environment/scripts/runtime.sh`.

## Operation interfaces
`bash scripts/project.sh project-plan REQUEST.json` produces an immutable operation plan. `project-apply` accepts that returned `details` as `plan`; this is the transaction API's stale-state boundary, not a prescribed Agent workflow.

Requests specify `software:"project"`, actual `targetId`, and `project.kind`, physical `path`, exact `runtimeVersion`, reviewed `sourceFiles`, `budgetBytes`, and `expectedOutput`. Node requires explicit `runScript` with optional `buildScript` and its existing npm lock. Python uses existing hashed requirements, a project venv and relative `entry`. Go uses go.mod/go.sum and an owned workspace artifact. No project kind or launch command is guessed.

The transaction records SDK/source/lock identities and declared effects. Work belongs to `.kai-project`; foreign pre-existing directories are preserved. SDK installation is separate. `needs-ai` reports unsupported facts without deciding a recipe. Building an artifact does not install it or prove the user task complete.

Crypto configuration is inherited by default. Explicit `project.cryptoPolicy:"sdk-default"` pins the exact configuration hash and creates a process-local copy in owned project space; firmware/CA/TLS policy is unchanged.
