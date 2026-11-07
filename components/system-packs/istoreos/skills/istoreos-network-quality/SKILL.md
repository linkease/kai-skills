---
name: istoreos-network-quality
description: 旧 iStoreOS ID 兼容入口；主实现为跨 Linux 的 kai-network-quality。
owner: system-pack/istoreos
systems: istoreos
alias-for: kai-network-quality
invocation: manual
auto-use: off
---

# Compatibility alias

Use `kai-network-quality` as the unique primary implementation. Existing native
scripts remain packaged as compatibility resources for older installations;
new routing, AI diagnosis and measurement use the canonical Linux skill.
