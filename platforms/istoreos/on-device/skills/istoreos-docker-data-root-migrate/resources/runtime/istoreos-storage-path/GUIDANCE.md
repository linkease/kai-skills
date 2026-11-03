---
name: istoreos-storage-path
description: 旧 ID 兼容入口；主实现为 kai-storage-files。
owner: system-pack/istoreos
systems: istoreos
alias-for: kai-storage-files
needs-fresh-data: true
invocation: manual
auto-use: off
---

Use `kai-storage-files` as the unique primary implementation. This retired ID is a migration alias. Native scripts remain only for existing platform helper interfaces; see data/legacy-contract.md when maintaining those interfaces.
