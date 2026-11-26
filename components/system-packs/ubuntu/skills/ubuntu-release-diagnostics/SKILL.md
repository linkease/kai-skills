---
name: ubuntu-release-diagnostics
description: Read Ubuntu release pockets, phased update metadata, snap, netplan and cloud-init facts without prerequisite skill routing.
owner: system-pack/ubuntu
systems: ubuntu
features: apt-get, systemctl
invocation: manual
resource-discovery: explicit
---

This documentation adapter provides optional Ubuntu-specific native sources: `/etc/os-release`, apt policy/pocket metadata, installed package records, existing snap metadata, netplan source files, cloud-init status/logs and systemd journal. Bound time and output explicitly; preserve source and missing/denied/timeout distinctions.

There is no prerequisite Debian skill pass. Ubuntu-specific and shared queries can be combined or omitted by the model. Queries do not refresh indexes, apply netplan, install tools, start services or repair cloud-init. Host kernel and container distribution remain different scopes.
