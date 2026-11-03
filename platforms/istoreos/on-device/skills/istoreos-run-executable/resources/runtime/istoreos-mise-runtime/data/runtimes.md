# Runtime selection and diagnosis

## Python

Inspect mise version/backend, `uname -m`, libc loader, CPU capabilities and published artifacts. The system integration source inspected supports x86_64/aarch64; Python precompiled availability is a separate question. Use baseline x86_64 unless a CPU-specific archive is deliberately verified; do not assume x86_64_v3 support. Match musl to unknown-linux-musl and glibc to unknown-linux-gnu only after libc detection. Unknown architectures need an actual compatible upstream archive/mise mapping, not a guessed mapping.

The public installer requires a full stable Python version and scopes `MISE_PYTHON_COMPILE=0` to prevent fallback. On mise 2026.8.14 the historical x86_64/musl workaround was:

```sh
# Inside mise-exec; this version is historical evidence, not today's latest.
MISE_PYTHON_COMPILE=0 MISE_PYTHON_PRECOMPILED_OS=unknown-linux-musl \
  MISE_PYTHON_PRECOMPILED_ARCH=x86_64 ks-cli mise install python@3.13.7
mise exec python@3.13.7 -- python --version
```

Prefer `install.sh` for provenance/module checks and preflight. A release not offering the exact compatible archive is precompiled-unavailable. Choose another user-compatible verified version or report the limit; do not remove COMPILE=0 to make it proceed. Source compilation is a separate explicitly requested workflow with dependencies/storage reviewed first.

If latest resolves implausibly, capture actual mise/backend versions, ls-remote inputs/cache state and the backend's exact sort invocation. Reproduce that invocation against a small numeric version list using the target's BusyBox/tool version. The session observed 3.9.9 ordered after 3.13.7/3.14.0 with python-build's parameters; it does not establish that all BusyBox sorts or mise versions fail. Do not install/replace sort or relabel a pinned workaround as latest.

| Evidence | Next diagnostic action |
| --- | --- |
| No matching precompiled archive / 404 | Check version, OS, arch, flavor and upstream release; distinguish a missing artifact from gateway failure |
| python-build/configure, no acceptable C compiler | Record compiler absence and compile settings; correct version/precompiled selection before considering a separately authorized build |
| ELF loader missing / illegal instruction | Recheck libc and CPU instruction requirements; a successful download is not a runnable runtime |
| python -m pip works, pip exits 127 and realpath missing | Inspect `command -v pip` and launcher. Create/activate a venv and test its pip directly. If another workflow needs realpath, discover its provider in actual feeds; do not guess a package or edit launcher files |
| System Python executes instead of installed version | Check mise where/exec, executable provenance and project/global selection |
| pip path outside VIRTUAL_ENV / externally managed environment | Re-enter the same shell, activate the project's venv, inspect sys.prefix/base_prefix; do not use system-wide pip or break-system-packages |

Verification imports ssl, sqlite3, bz2, lzma, ctypes and venv and checks pip as a module. Runtime-install logs must retain applicable checksum/attestation success. Dependency acceptance additionally tests the actual `ks-cli pip` executable, import and pip check in the venv.

## Node.js

Resolve a requested numeric prefix or lts to a complete version before installation; preserve the user's requested constraint. With compatible mise (ks-cli baseline 2026.4.23), let mise choose the platform and published artifact. musl unofficial-builds and glibc official nodejs.org have different archive/signature availability; do not manually set one shared mirror for both. Consult the target mise version's behavior; upstream docs evolve.

ks-cli replaces final official/unofficial URLs and matching GitHub Release URLs, not every backend network call. Keep node.verify and checksum enabled. Inspect real backend settings: mise 2026.8.14 has go.skip_checksum, not a global skip_checksum; an unknown setting is a contract mismatch, not evidence of disabled checksums. Optional unset gpg_verify/node.gpg_verify values retain backend defaults; explicit false is rejected. This was checked against the installed CLI and [the pinned setting schema](https://raw.githubusercontent.com/jdx/mise/v2026.8.14/settings.toml). A persisted custom mirror requires inspection; the public installer does not erase it. An unofficial detached signature's true 404 is distinct from disabling signature verification: the backend may continue SHA-256 where no signature is published. Official signature and checksum verification must still run. Unexpected 200 with empty signature data or checksum mismatch is a failed install, not a reason to skip verification.

Validate full archive download/checksum/extraction plus Node's actual executable/version and npm --version. ls-remote or index.json alone is insufficient. The user session has no completed Node/npm device validation; historical other-architecture results remain historical.

## Go SDK

Install/resolve the SDK through ks-cli mise and verify `mise where go@VERSION`, `go env GOROOT` and exact go version inside explicit mise exec. SDK tarball/checksum use the go-sdk route; Go modules use the golang proxy protocol later. Keep the requested SDK explicit and disable unplanned toolchain switching in a dependency test (`GOTOOLCHAIN=local`). No module download success can prove an SDK was installed by mise.

## Network failures

Check `ks-cli status --json`, `ks-cli doctor mise --json` and `ks-cli --explain --json mise install RUNTIME@VERSION`. Doctor/explain are preflight, not successful downloads. Inspect UCI's installed ports rather than copying 5443/5003; check loopback resolution, TLS certificate/system time, capabilities and gateway logs. A doctor hint to upgrade on OpenWrt goes through package-manager/iStore, never the ordinary Linux installer. Preserve backend scope: external scripts, Git and nonmatching origins may remain direct.
