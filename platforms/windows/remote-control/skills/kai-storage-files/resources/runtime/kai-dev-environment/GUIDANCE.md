---
name: kai-dev-environment
description: 用 mise 安装、验证和执行 Python、Node、Go SDK 与开发 CLI。
owner: system-pack/common
systems: ubuntu, debian, istoreos, openwrt, linux, macos, windows
triggers: 安装 Python, 安装 Node, 安装 node, 安装 Go, 安装 golang, 开发环境, 安装开发 CLI, SDK, python-build, 解释器异常
negative-triggers: pip install, npm ci, go mod, uv sync
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
aliases: istoreos-mise-runtime
---

Before calling Bash scripts, prepare an existing compatible Bash with kai-tool-bootstrap. On Windows the first Bash bootstrap uses native PowerShell. Follow the selected target Transport; the controller OS does not choose the target package manager.

Use the target's platform and Transport. Discover/ensure mise with
kai-tool-bootstrap. System packages belong to kai-software; npm/pip/uv/Go project
dependencies belong to kai-project-dependencies. Installation authorization does
not imply changing a global default.

Run `bash scripts/runtime.sh probe RUNTIME EXACT_VERSION` without installing.
Missing SDKs return runtime-not-installed. `install RUNTIME EXACT_VERSION
[none|project|global]` installs and verifies; default none changes no selection.
Use project only for an authorized project configuration edit, global only when
explicitly requested. Complete stable versions are required; resolve ambiguous
requests with `resolve RUNTIME SELECTOR` against mise's actual catalog before
installing. Resolution never installs or selects a default. Do not hardcode a
historical test version as latest.

`verify RUNTIME EXACT_VERSION` checks the selected installation's provenance and
version. Python verifies ssl/sqlite3/bz2/lzma/ctypes/venv and pip; Node executes a
script and checks npm; Go checks its SDK root and version. Run the user's program
with `exec RUNTIME EXACT_VERSION -- COMMAND [ARG...]`; each independent call
selects the SDK again. Go compilation and dependency imports still need actual
project execution before declaring the user's task complete.

On iStoreOS/OpenWrt, every independent call enters the real mise-exec integration
through its file/argv adapter. Missing UCI, runtime_dir or integration fails;
ordinary Linux/macOS/Windows never use iStore HOME. Windows uses Git Bash and
native mise with Windows paths for SDK checks; WSL remains its own Linux target.

Python uses precompiled-only mode. Unknown libc/architecture or absent prebuilt
artifacts fail; never install a compiler or compile implicitly. Node verification
and Go checksums remain enabled in the installation process. Do not weaken TLS,
signatures or hashes to recover a download. Native failures keep their code;
provenance/functional failures return runtime-verification-failed.

Runtime success proves the SDK. Gateway traversal requires the separate
kai-download-acceleration evidence workflow; plain mise success cannot prove it.
After confirming a ready gateway, `KAI_RUNTIME_ACCELERATION=required` delegates
installation and exec to the existing ks-cli mise interface. It never installs
or starts a gateway. A client failure remains a failure, with its original code;
there is no silent direct retry. Probe and provenance checks remain local.

For a failed installation, save the current Transport stderr and run
`bash scripts/diagnose.sh LOG_FILE ORIGINAL_EXIT_CODE`. It distinguishes version,
prebuilt availability, environment, download, TLS and integrity evidence and
retains the original code. Diagnosis never retries or modifies the target.

On the locked iStoreOS default, bundled Python OpenSSL can reject the firmware's
empty ENGINE initializer. Python tasks use a SHA-locked copy under runtime HOME
that omits only that initializer. Providers, diagnostics and CA paths remain;
system files/curl are untouched. Custom crypto extensions block this adapter,
and an explicit OPENSSL_CONF is preserved. Continue using this entrypoint for
each Python/venv call so the process-scoped configuration is applied consistently.

Go catalog lookup may fall back to native Git. Ensure Git with HTTPS transport
through kai-software when required; do not upgrade system curl to satisfy it.
For the public Go catalog, `KAI_GO_GIT_METADATA=required` together with explicit
runtime acceleration obtains a read-only Git Doctor/Explain plan and applies
only its process-scoped Git settings. The existing client's credential isolation
and actual gateway port are retained; global Git configuration is untouched.
This public-mirror mode is not a private-repository workflow. Version/API/source
failures keep their original code; do not replace checksums or disable TLS.

For the first standalone development CLI profile, use `bash scripts/dev-cli.sh
probe|install|exec uv EXACT_VERSION [-- ARGUMENTS]`. Probe only inspects an
already installed version. Explicit install uses mise without changing a global
selection, with the existing acceleration option when required. Executable
lookup uses mise's version-specific `which --tool` and checks that its resolved
path stays inside that installation; exec uses that exact path. The actual
version and subcommand still need validation. Other CLI profiles return an
explicit unsupported result. Use kai-project-dependencies for uv package work.
