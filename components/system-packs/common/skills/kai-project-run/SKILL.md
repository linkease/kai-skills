---
name: kai-project-run
description: Plan or execute an explicitly selected Node, Python or Go project transaction with exact SDK, source hashes, locks and expected output.
resource-discovery: explicit
---

`bash scripts/project.sh project-plan REQUEST.json` produces an immutable operation plan. `project-apply` accepts that returned `details` as `plan`; this is the transaction API's stale-state boundary, not a prescribed Agent workflow.

Requests specify `software:"project"`, actual `targetId`, and `project.kind`, physical `path`, exact `runtimeVersion`, reviewed `sourceFiles`, `budgetBytes`, and `expectedOutput`. Node requires explicit `runScript` with optional `buildScript` and its existing npm lock. Python uses existing hashed requirements, a project venv and relative `entry`. Go uses go.mod/go.sum and an owned workspace artifact. No project kind or launch command is guessed.

The transaction records SDK/source/lock identities and declared effects. Work belongs to `.kai-project`; foreign pre-existing directories are preserved. SDK installation is separate. `needs-ai` reports unsupported facts without deciding a recipe. Building an artifact does not install it or prove the user task complete.

Crypto configuration is inherited by default. Explicit `project.cryptoPolicy:"sdk-default"` pins the exact configuration hash and creates a process-local copy in owned project space; firmware/CA/TLS policy is unchanged.
