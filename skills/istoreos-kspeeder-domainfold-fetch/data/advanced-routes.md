# Advanced runtime routes

Read only the section matching the active task.

## Python/Node.js/Go and ecosystem dependencies

Runtime SDK installation belongs to `kai-dev-environment`: discover the integrated system package, enter mise-exec, select an explicit compatible version and retain integrity verification. Use its exec.sh for noninteractive commands; mise-exec does not forward argv. Preserve the system-managed HOME.

pip/npm/Go modules belong to `kai-download-acceleration`: its isolated smoke recipes use a Python venv, real npm dependencies and Go require/import, plus matching current-instance index/module and artifact evidence. Use ks-cli adapters and the actual configured ports. Keep TLS, signatures, checksum and sumdb enabled; report observed direct fallback separately.

Do not turn this Git/file remapping helper into another runtime installer or a global dependency configuration path. Downloading an index alone does not validate an SDK or dependency installation.

## Homebrew

Free mode accelerates metadata:

```sh
eval "$(iStoreEnhance brew-env --mode free)"
brew install <formula>
```

Plus mode may additionally route GHCR-backed bottles:

```sh
eval "$(iStoreEnhance brew-env --mode plus)"
brew install <formula>
```

Do not replace the GHCR bottle path with legacy `HOMEBREW_BOTTLE_DOMAIN`.

## Source-specific rule

These routes are product defaults, not universal Internet mirrors. Check current
device readiness and use direct download as the fallback when a route is absent
or unhealthy.
