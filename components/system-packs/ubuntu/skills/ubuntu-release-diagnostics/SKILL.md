---
name: ubuntu-release-diagnostics
description: Ubuntu-specific read-only checks for release pockets, phased updates, snaps, netplan, cloud-init, and service failures; use only after the shared Debian evidence pass.
owner: system-pack/ubuntu
systems: ubuntu
features: apt-get, systemctl
invocation: manual
---

# Ubuntu Release Diagnostics

Use this overlay only for Ubuntu-specific behavior. Start with the Debian
diagnostic evidence, then inspect only the relevant release pocket, phased
update, snap, netplan, or cloud-init state.

Keep journal and package output bounded. Ask before package changes, service
changes, network configuration, snap operations, or writing cloud-init files.
