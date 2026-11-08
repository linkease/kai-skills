---
name: kai-project-run
description: Build and run an existing Node, Python or Go project using a selected SDK and its existing dependency locks; hand unsupported build recipes to AI.
---

Use the selected target's Bash and full jq. Run `scripts/project.sh project-plan REQUEST.json`,
then pass the returned `details` as `plan` to `project-apply` within the user's project authorization.
Requests use `software: "project"`, the actual `targetId`, and `project` with physical `path`,
exact `runtimeVersion`, reviewed `sourceFiles`, `budgetBytes` and `expectedOutput`.
Node uses an existing npm lock and `runScript` (default `start`), plus optional `buildScript`.
Python uses the existing hashed requirements.txt, a project venv and relative `entry`.
Go uses go.mod/go.sum, builds an owned workspace artifact and runs that artifact.

SDK installation is a separate preparation through kai-dev-environment. Project dependencies
reuse kai-project-dependencies. Plans identify SDK, source/lock hashes, disk budget and effects.
Keep project/global configuration and lock formats. Work/cache/output belongs in the project's
`.kai-project`; preserve a pre-existing unowned directory.

On `needs-ai`, use the returned attempted/required facts to choose a build recipe or make an
explicit source change, then generate a new plan. Do not repeat an unchanged failed recipe.
An AI-produced binary is a candidate until its platform, SHA256, functional check and install
ownership have passed the software task's artifact flow; building alone does not install it.

Python inherits target crypto configuration by default. If that policy is incompatible,
return its failure. A project that needs the SDK's default provider may explicitly set
`project.cryptoPolicy: "sdk-default"`; the plan records the exact config hash, and execution
creates that config in owned project space and exports it only to the SDK process tree.
This choice does not enable firmware legacy algorithms inside the SDK or change firmware,
CA paths, certificate checks or other programs' crypto policy.
