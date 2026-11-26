---
name: debian-system-diagnostics
description: Read Debian release, package database, systemd registration, journal, mounts and sockets through existing native tools.
owner: system-pack/debian
systems: debian, ubuntu
features: apt-get, systemctl
invocation: manual
resource-discovery: explicit
---

This documentation adapter describes native read interfaces: `/etc/os-release`, `dpkg-query`, `apt-cache`, `systemctl show`, bounded `journalctl`, `df`, `mount`, `ps` and `ss`. Commands run on the bound target; unsupported tools and permission failures remain unknown rather than triggering installation.

No prescribed diagnostic sequence or repair is implied. Package cache and installed versions differ; systemd running and an application's actual API health differ. Queries do not refresh feeds, install packages, start services or change network/storage configuration. Generic tools remain available.
