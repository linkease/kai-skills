---
name: kai-project-dependencies
description: 在所选 mise SDK 和项目隔离环境中安装 npm、pip、uv、Go 依赖。
owner: system-pack/common
systems: ubuntu, debian, istoreos, openwrt, linux, macos, windows
triggers: pip install, npm install, npm ci, go mod, uv sync, Python 依赖, 项目依赖, 验证 Python 依赖安装流程
negative-triggers: 安装 Python, 安装 Node, 安装 Go, 系统软件包
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
---

Before calling Bash scripts, prepare an existing compatible Bash with kai-tool-bootstrap. On Windows the first Bash bootstrap uses native PowerShell. Follow the selected target Transport; the controller OS does not choose the target package manager.

Use the target's platform and Transport. System libraries/packages belong to
kai-software; SDK installation and exact version resolution belong to
kai-dev-environment. Verify the selected SDK first. Keep the project's existing
package manager; do not convert npm to another manager or pip to a uv project.

Run `bash scripts/dependencies.sh install MANAGER EXACT_RUNTIME_VERSION PROJECT`.
The project must already exist. npm uses its existing package-lock.json with ci;
pip creates/re-enters PROJECT/.venv and installs requirements.txt; uv uses the
same selected Python with an existing uv.lock or requirements.txt; Go downloads
and verifies modules. Existing locks are checked for changes. A conflicting or
foreign venv is preserved. Every independent call selects the SDK again, including
the real iStoreOS/OpenWrt runtime integration. Windows uses Git Bash and the
native Python Scripts layout. Do not substitute system Python or global packages.
Windows npm executes the selected SDK's `node.exe` with its own npm JS entry;
pip executes the project `Scripts/python.exe -m pip`. This preserves literal
arguments without relying on batch shims. For required acceleration, a passing
Doctor and a validated read-only ks-cli Explain plan supply only that manager's
HTTPS registry/index to the current process. No global configuration is written.
MSYS conversion is controlled for the known native child after its script path
is converted, rather than disabled in the user's shell.

uv must already be installed at an exact `KAI_UV_VERSION`; it is selected through
mise, its executable/version checked, and managed Python downloads disabled.
Install the authorized uv version inside the selected runtime environment with
`runtime.sh exec python VERSION -- mise install uv@UV_VERSION`, using the
kai-dev-environment entrypoint. This changes no global selection. If acceleration
is required, run the inner installation through the existing ks-cli mise command.

`run MANAGER VERSION PROJECT -- ARGS...` forwards literal native package-manager
arguments in that project environment. For explicit dependency changes,
`add npm VERSION PROJECT -- PACKAGE@VERSION` uses --save-exact; `add go ... --
MODULE@VERSION` uses go get. For a uv project use an explicit `run uv ... -- add`
operation. Python requirements edits follow that project's own lock workflow;
the helper does not rewrite them from an ambient pip freeze.

Use `sources MANAGER VERSION PROJECT` for read-only source hints. Git, direct
URLs, local dependencies, private registries and Go private-module policy need
separate source review; ordinary registry routing does not cover them all.
Source hints do not establish acceleration. uv TOML hints are not a full resolver.

`KAI_DEP_ACCELERATION=required` requires an existing ks-cli and a passing read-only
Doctor for that manager before delegating native commands. It does not issue
service installation/start commands. Establish an authorized ready gateway with
kai-download-acceleration first; failed readiness is not a reason to install one
inside a dependency task. Client failures retain their original code and stderr.
TLS, package hashes and Go sumdb remain enabled. Inspect native-library errors
with kai-software; do not install compilers/system libraries implicitly.

Installation receipts have functionalValidation=not-run. Execute/import the
actual project before reporting success; use the selected runtime entrypoint for
each call and its project venv interpreter for Python. Confirm expected output,
lock integrity and that global npm/pip/Go configuration stayed unchanged.
Acceleration additionally requires current-instance gateway evidence.
