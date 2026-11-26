---
name: macos-system-diagnostics
description: Read bounded native macOS system, tool and optional Docker facts from the actual target.
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.

## Local supporting resources

- `kai-system-information`: [local instructions](resources/runtime/kai-system-information/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

## Operation interfaces
`sh scripts/inspect.sh` delegates the shared system.inspect contract. It does not install dependencies, start Docker, choose an installation method or infer task completion. Query scope, unsupported providers, permission failures and timeouts are explicit. Native package manager and container client/engine observations remain separate.
