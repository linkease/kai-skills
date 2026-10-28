---
name: istoreos-download-acceleration
description: 旧 ID 兼容入口；主实现为 kai-download-acceleration。
owner: system-pack/istoreos
systems: istoreos
alias-for: kai-download-acceleration
needs-fresh-data: true
invocation: manual
auto-use: off
---

Use `kai-download-acceleration` as the unique primary implementation. This retired ID is a migration alias. Native scripts remain only for existing platform helper interfaces; see data/legacy-contract.md when maintaining those interfaces.
