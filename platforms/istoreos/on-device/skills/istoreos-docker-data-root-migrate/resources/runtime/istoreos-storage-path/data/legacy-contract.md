# Storage interface compatibility

`detect.sh` returns filesystem observations, not a chosen base path. `probe.sh ABSOLUTE_DIRECTORY` performs an explicitly authorized write probe in an existing physical directory using only an owned mktemp file. No parent directories are created.

Historical is-opkg AUTOCONF uses a supplied base to derive Configs, Caches, Public and Public/Downloads. These names describe that native API, not an installation location selection policy. App subdirectories belong to the selected native application contract. Mount capacity, persistence and permissions are separate facts; no disk is preferred by this adapter.
