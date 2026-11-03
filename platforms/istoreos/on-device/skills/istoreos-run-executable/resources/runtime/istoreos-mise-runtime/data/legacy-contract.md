# Legacy native interface reference


# iStoreOS Runtime Environment

Use for iStoreOS/OpenWrt with iStore runtime integration. Ubuntu uses its own Linux runtime workflow; do not prescribe iStore HOME, UCI or mise-exec there. Installation authorization does not imply global version/configuration changes. For read-only probes set MISE_AUTO_INSTALL=0 and MISE_NOT_FOUND_AUTO_INSTALL=0; do not trigger missing SDK installs through shims or mise exec.

## Workflow

1. Run `sh scripts/check.sh [python|node|go|all]` for read-only system facts: release, architecture/libc, package manager, runtime_dir and space. Its executable paths describe the current shell, not selected mise SDKs; it never enters mise-exec. Unknown libc/arch needs evidence. Verify persistent storage/mounts before installing; inspect overlay or low space with storage-path.
2. If integration is absent, use package-manager to discover and install the actual feed's integrated mise package. Verify mise-exec, mise, integration files and configured runtime_dir; no upstream curl bypass. Source package names do not prove feed availability.
3. Enter `mise-exec`, then run mise, ks-cli and runtime/dependency commands in that shell. mise-exec does not forward command arguments: never use `mise-exec sh -c ...` or `mise-exec -- COMMAND`. HOME and shims come from system integration; cwd is chosen separately. For local/remote noninteractive calls use `scripts/exec.sh PROGRAM_FILE [ARG...]`; it launches the staged program in the shell's environment. Each independent call re-enters integration. Read `data/execution.md` when transport or legacy acceleration matters.
4. For an installed complete version run `sh scripts/probe.sh RUNTIME RESOLVED_VERSION`. It re-enters integration, disables auto-install and emits JSON after checking SDK provenance/version/functionality. Diagnostics go to stderr. System executable observations cannot override this result. For an unresolved version inspect the actual backend/platform inside exec.sh; Python needs a verified complete version, not an anomalous latest result. Node lts is an option without a requested version.
5. Run `KAIPLUS_CONFIRMED=1 sh scripts/install.sh <python|node|go> <version> [none|project|global]`. It enters mise-exec itself, uses ks-cli preflight/install and verifies the exact installed runtime. Default `none` installs without selecting a global version. `project` changes the current project's mise configuration; `global` changes this integrated HOME's global selection.
6. For dependencies, continue with download-acceleration inside the same environment; Python defaults to an activated project venv. Package downloads inside a runtime command are not automatically accelerated by ks-cli mise.

## Installation versus activation

`mise install` stores a runtime. `mise use VERSION` selects a project version (and may install); `--global` changes the integrated HOME's default. Shims choose from the current configuration. `mise exec VERSION -- COMMAND` chooses a version for that process and its children without a persistent selection; do not mistake an existing system Python on PATH for mise success.

`verify.sh RUNTIME RESOLVED_VERSION` checks install-root provenance plus exact version and runtime functionality. Verification disables automatic missing-runtime installation. Python checks ssl/sqlite3/bz2/lzma/ctypes/venv and python -m pip, but this alone does not verify the pip launcher used by ks-cli pip.

Prefer probe.sh for Agent checks and install.sh for installation; both report scoped JSON results. `runtime_validation=passed` proves the selected SDK, not dependency downloads or gateway traversal. Custom project commands still use exec.sh PROGRAM_FILE. These are skill-owned entrypoints, not Kai-wide command interception. Read `data/execution.md` for result fields and authorization of native mise-exec's setup/probe effects.

## Runtime-specific decisions

Read only the needed section in `data/runtimes.md` for Python precompiled arch/libc and latest/sort diagnosis, Node official/unofficial artifacts and integrity, or Go SDK provenance. Python installation forces precompiled mode; no matching artifact must stop rather than install compilers or silently build from source. Explicit 3.13.7 is historical x86_64/musl evidence, never a permanent latest version.

The legacy integration can set a Node mirror and verification=0. The installer clears that mirror in its process, enables Node verification, and rejects persisted custom mirrors or disabled checksum/signature settings. It preserves system HOME/shims and uses ks-cli's actual-port URLs; it does not change global mise configuration for acceleration.

## Failure handling

Use `sh scripts/diagnose.sh LOG_FILE` with current evidence. Distinguish version selection, missing precompiled artifact, source build/compiler absence, pip-launcher realpath, inactive venv, download and integrity/TLS failures. Keep the original exit code. For gateway failures inspect service health/capabilities, actual ports, DNS/TLS and request logs; use system packages/iStore for missing or outdated service components. Never disable verification or promise all backends/Git sources are mirrored.
