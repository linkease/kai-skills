# Legacy native interface reference


# iStoreOS Package Manager

Apply this distribution skill to iStoreOS and the detected OpenWrt integration. Ubuntu and other ordinary Linux distributions use their own package skills; the presence of opkg/apk on PATH alone is not an OS identity.

## Detect before choosing commands

1. Run `sh scripts/package.sh detect`: it checks OpenWrt identity, active package database and executable. `is-opkg` is an opkg lifecycle wrapper, not a separate database. If both databases are present, or a database/tool is missing, inspect before choosing. Do not infer the package manager from the release number.
2. Query cached feeds with `search`, `available` and `info`. These do not refresh indexes. Inspect configured feeds/repositories and architecture; a package in a source repository is not proof it is in this device's feed. If the index needs refresh, explain that write and use the authorized `refresh` action; never suppress its failure.
3. Distinguish iStore meta, ordinary system package, and Docker-style iStore app. Meta names come from the full Store catalog or actual local metadata, not guessed app names. On apk images, verify whether iStore meta/is-opkg integration exists instead of assuming opkg metadata paths.

## Find and install

- For a functional description or multiple iStore candidates, use `istoreos-app-search` and show up to three names, source/type, compatibility, fit and entrypoint. Select a concrete candidate before installation. Missing local meta does not mean missing from Store; app-hub is not the full Store catalog.
- For system packages use `sh scripts/package.sh search <term>`, then `available <exact-package>` and `info <exact-package>`. For installed files use `files <package>` or `owner /absolute/file`.
- Existing opkg callers may keep `opkg-find.sh <regexp> [limit]`, `opkg-info.sh <pkg|regexp> [limit]` and `opkg-search-file.sh <file|pattern> [limit]`; these preserve query arguments without implicit refresh. On apk use the native `package.sh` actions above; the legacy opkg query dialect is not portable.
- After the requested package/source/architecture and effects are authorized, use `KAIPLUS_CONFIRMED=1 sh scripts/package.sh install <exact-package>`; similarly `upgrade` or `remove`. It uses is-opkg/opkg install on an opkg image and apk add on an apk image. Never bypass signature or TLS checks.
- An iStore meta package is `app-meta-<verified-name>` only when that exact feed candidate exists. Use supported is-opkg autoconf for its configuration; do not copy that opkg-specific contract onto apk.
- Mise prerequisite: discover the integrated package in the target's actual feeds, inspect its files/integration, install through this manager, then verify `mise`, `mise-exec`, `/lib/functions/mise.sh` and UCI runtime_dir. A bare upstream mise package without iStore integration is not enough. Return to `istoreos-mise-runtime`; do not use the upstream curl installer.
- No matching integrated package: report unsupported feed/architecture or stale indexes. Use supported system/iStore setup or request a compatible image/feed; do not invent a package name or force another distribution's package.

## Services and Docker apps

Meta containing docker-deps or an installed `/usr/libexec/istorec/<name>.sh` selects the Docker app lane. Use `istoreos-docker-basics` for space checks and `istoreos-docker-acceleration-istoreenhance` for readiness before pulls. Preserve the app's own persistent-directory/autoconf rules.

For an installed system package, inspect `files` for `/etc/init.d/` and UCI configuration, then use the service-manager helper with authorized effects. `ensure_services_from_pkg.sh` supports either database; it does not hide service failures. No systemctl on OpenWrt. A doctor hint to upgrade KSpeeder means the detected package/iStore update path, not the ordinary Linux ks-cli installer.

## Verify and diagnose

Use `installed <package>` plus the actual executable, LuCI entry or service status. APK/opkg package status alone does not prove the runtime shell is integrated. For Docker apps also check istorec status or the actual container.

For iStore task failures use `istoreos-app-diagnostics/scripts/inspect.sh <app-id>` and honor its correlation/next-helper result. Do not attribute stale or mismatched task logs to the current app. Unknown failures go to logs-and-diagnostics with package, source, space and exit-code evidence. File downloads and pip/npm/Go modules belong to download-acceleration; Python/Node/Go SDK versions belong to mise-runtime.
