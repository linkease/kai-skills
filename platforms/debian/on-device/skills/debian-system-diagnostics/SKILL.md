---
name: debian-system-diagnostics
description: Read-only Debian diagnosis using os-release, systemd journal, apt/dpkg state, storage, processes, sockets, and bounded service logs before proposing a repair.
owner: system-pack/debian
systems: debian, ubuntu
features: apt-get, systemctl
invocation: manual
---

# Debian System Diagnostics

Collect a small evidence set before recommending changes:

1. Read `/etc/os-release`, architecture, uptime, memory, filesystems, and mounts.
2. Inspect the relevant `dpkg-query`, `apt-cache policy`, and `systemctl status` output.
3. Read only the affected unit's bounded journal excerpt; never inject the full journal into context.
4. Explain the observed failure and the smallest proposed action.
5. Ask for confirmation before `apt install/remove/upgrade`, changing files, or changing service state.

Do not assume OpenWrt, `opkg`, `procd`, iStore, ASUSWRT, or Koolshare conventions.
