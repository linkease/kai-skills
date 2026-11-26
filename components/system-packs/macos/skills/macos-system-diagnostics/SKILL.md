---
name: macos-system-diagnostics
description: Read bounded native macOS system, tool and optional Docker facts from the actual target.
owner: system-pack/macos
systems: macos
requires: target-shell:posix
triggers: macOS 异常, Mac 诊断, 系统变慢, 磁盘空间, memory pressure, macOS health
auto-use: suggest
needs-fresh-data: true
cost: low
resource-discovery: explicit
---

`sh scripts/inspect.sh` delegates the shared system.inspect contract. It does not install dependencies, start Docker, choose an installation method or infer task completion. Query scope, unsupported providers, permission failures and timeouts are explicit. Native package manager and container client/engine observations remain separate.
