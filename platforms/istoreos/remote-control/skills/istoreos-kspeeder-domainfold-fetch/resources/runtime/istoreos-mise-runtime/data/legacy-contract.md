# Native SDK interface compatibility

`check.sh [python|node|go|all]` reads current shell integration facts; `probe.sh RUNTIME FULL_VERSION` enters the selected native integration and verifies provenance/version. Read probes disable missing-runtime auto-install. A current-shell interpreter is distinct from an explicitly selected SDK.

`install.sh RUNTIME FULL_VERSION [none|project|global]` is an explicitly authorized SDK transaction; none installs without changing selection. Project/global choices change those exact scopes. `exec.sh PROGRAM_FILE [ARG...]` stages and runs a literal program through native mise-exec stdin; that integration does not forward CLI arguments and is not `mise-exec -- COMMAND`. Each call has its own process environment. `verify.sh` and `diagnose.sh LOG_FILE` provide scoped verification or heuristic evidence without task routing.

`runtime_validation=passed` verifies the selected SDK, not dependencies, gateway traversal or a complete user task. Precompiled Python selection, Node verification and SDK integrity are native transaction constraints. Unsupported artifacts do not trigger compiler installation or signature/TLS bypass. [Execution fields](execution.md) and [runtime facts](runtimes.md) preserve the detailed integration contract. Version 3.13.7 is historical test evidence, not latest.
