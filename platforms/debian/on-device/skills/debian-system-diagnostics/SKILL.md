---
name: debian-system-diagnostics
description: Read Debian release, package database, systemd registration, journal, mounts and sockets through existing native tools.
metadata:
  opencode/autoinvoke: "false"
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.
This documentation adapter describes native read interfaces: `/etc/os-release`, `dpkg-query`, `apt-cache`, `systemctl show`, bounded `journalctl`, `df`, `mount`, `ps` and `ss`. Commands run on the bound target; unsupported tools and permission failures remain unknown rather than triggering installation.

No prescribed diagnostic sequence or repair is implied. Package cache and installed versions differ; systemd running and an application's actual API health differ. Queries do not refresh feeds, install packages, start services or change network/storage configuration. Generic tools remain available.
