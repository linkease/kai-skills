# Native package interface compatibility

`package.sh detect` reports actual OpenWrt identity, tool and database evidence; opkg/is-opkg share a database, APK is distinct. Both databases or missing tools remain explicit conflicts. Release numbers do not select a manager.

Queries `search`, `available`, `info`, `installed`, `files` and `owner` read existing metadata without refresh. `refresh`, `install`, `upgrade` and `remove` are explicit native mutations with the selected package identity and existing authorization. TLS/signature checks remain enabled. Legacy opkg query dialects are not portable APK APIs.

Store meta, system packages and Docker applications are distinct identities. Feed/source architecture availability is not proved by repository files. Package registration does not prove executable, web or service health. `ensure_services_from_pkg.sh REQUEST.json` is now a single service.apply compatibility alias, not a package-wide service workflow. It never discovers and activates a package's services.

Static integration facts include mise, mise-exec, /lib/functions/mise.sh and runtime_dir. Their presence and compatibility are independent observations, not an instruction to install a guessed package or follow another skill. Legacy app diagnostics next fields are null; classification is evidence, not a repair route.
