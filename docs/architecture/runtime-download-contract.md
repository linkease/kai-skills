# Runtime and dependency download contract

## System boundaries

| Target facts | System package ownership | Runtime environment |
| --- | --- | --- |
| Ubuntu or another ordinary Linux distribution | Its detected package manager; do not suggest opkg/apk merely because they are on PATH | Its existing mise installation and normal HOME; iStore `mise-exec` is not required |
| OpenWrt with iStore runtime integration | Active opkg/is-opkg or apk database and configured feeds | Install the feed's integrated package, then enter its `mise-exec` shell |
| OpenWrt without that integration | Its actual package manager and feeds | Report the missing integration; do not create an iStore HOME, assume a Runtime path, or use the upstream curl installer as an integration substitute |
| iStoreOS | Same fact-based opkg/is-opkg or apk selection, with iStore meta when available | System-managed runtime directory, HOME and shims |

This work updates the iStoreOS distribution pack, which extends OpenWrt and Linux. It does not turn iStoreOS skills into Ubuntu skills or add an Ubuntu preset to the public catalog. Other distribution packs retain their own policies. Reject a mismatched target before running an iStore integration helper.

## Frozen implementation evidence

Initial inspected revisions: linkease-skills `e5ba9ec05cc6c1160242084e65277a2723a8539c`; kspeeder `f403d6c92adbf288cee74a349ff95222f3849226`; Reasonix/Kai `65b25b166cbc1e615e1282f609a1b60bba2106c9`.

- The system mise package source is `istoreos-app-hub/apps/mise/mise`: package `mise`, mise 2026.8.14, x86_64/aarch64 at this revision. A source definition is not proof of availability in a device's feeds. Verify feed candidates and installed files before generating an installation command.
- `mise-exec` sources `/lib/functions/mise.sh`, applies `istore_runtime_env`, and executes `/bin/ash` without forwarding arguments. It is a shell entrypoint, not `mise-exec -- command`. The helper sets HOME from `mise.main.runtime_dir` (or the existing HOME fallback), prepends shims and supplies acceleration variables. It may create the runtime directory. It does not `cd` into it. An unconfigured integration is not a successful persistent-directory check.
- At the inspected plugin revision, acceleration can inject `MISE_NODE_MIRROR_URL` and `MISE_NODE_VERIFY=0`, probing default admin/TLS ports. Treat these as legacy environment input. Preserve HOME and shims, but restore verified Node selection/integrity in the command scope and let ks-cli inject actual gateway URLs; never persist an insecure setting.
- ks-cli inherits PATH/HOME and executes the native tool. It does not install mise or activate a venv. `pip` means the actual `pip` executable, not `python -m pip`.
- Network operations perform tool compatibility, service readiness and capability negotiation. `ks-cli doctor TOOL --json` checks without executing the tool; `ks-cli --explain --json TOOL ...` describes a plan and is not download evidence. Mise's current ks-cli minimum is 2026.4.23.
- On OpenWrt, UCI and `/etc/init.d/istoreenhance` own service configuration/control. Ordinary Linux `ks-cli service install/upgrade/uninstall` is not the package installation path. Translate a doctor upgrade hint to the detected system package manager/iStore. Discover TLS/admin ports from the installed instance; 5443/5003 are defaults only when permitted fields are absent.

kspeeder sources: `kspeeder-cli/internal/app/{tool_command,tool_doctor,openwrt,health}.go`, `kspeeder/downloadcmd/{gateway,gateway_mirror,gateway_route_selector}.go`; contracts: `kspeeder-cli/docs/ks-cli-openwrt-contract.zh-CN.md`, `kspeeder/docs/ks-cli-mise-acceleration.zh-CN.md`.

## Download lanes and integrity

| Work | Entry | Coverage and limits |
| --- | --- | --- |
| System packages | Detected package manager | Its configured feeds, signatures and package lifecycle |
| Python/Node/Go SDK | `ks-cli mise ...` inside integration shell | Go SDK mirror and allowlisted final Node/GitHub Release URL replacements; external backend scripts/Git/other origins are not automatically covered |
| Python packages | Activated project venv, `ks-cli pip ...` | PyPI index and rewritten metadata/wheel links; preserve TLS and package verification |
| npm packages | Project directory, `ks-cli npm ...` | Registry metadata and supported tarballs; preserve lockfile integrity; Git/nonregistry dependencies need separate diagnosis |
| Go modules | Project with require/import, `ks-cli go ...` | Go proxy protocol with `,direct` fallback; preserve go.sum and sumdb; distinct from SDK installation |
| Files / public Git / Docker | Existing file / Git remap / registry lanes | Keep their separate protocol and ownership rules |

Gateway-selected origin traffic is still gateway traffic. A client's direct fallback is different. Require client URLs and matching gateway GET/done evidence for index/module metadata and artifacts; environment values, cache hits and success alone do not prove the path. Do not disable TLS, checksum, attestations, GPG, signatures or sumdb to recover an installation.

## Historical device evidence (not this change's tests)

- User-reported iStoreOS 24.10.1 x86_64/musl, mise 2026.8.14: unqualified Python latest resolved to 3.9.9 and python-build failed without gcc/cc. The observed BusyBox sort ordering is a compatibility hypothesis scoped to that input/version, not a universal OpenWrt defect.
- Explicit Python 3.13.7 with `MISE_PYTHON_COMPILE=0`, `MISE_PYTHON_PRECOMPILED_OS=unknown-linux-musl`, `MISE_PYTHON_PRECOMPILED_ARCH=x86_64` downloaded, passed artifact attestations and ran ssl/sqlite3/bz2/lzma/ctypes/venv/pip checks. This is a workaround example, never a permanent latest alias.
- The global pip launcher failed because realpath was absent. An activated venv allowed `ks-cli pip install --no-cache-dir -v idna==3.10`; index and wheel/metadata hosts were `dl-pypi` and `dl-pypi-files`. Port 5443 was device-specific evidence. Add import and pip-check verification to the maintained recipe.
- User confirmed uuid v1.6.0 download/verify/run with require/import and an isolated GOMODCACHE.
- Node installation and npm dependency execution have no successful evidence in this user session. Historical arm64 installation records in kspeeder docs do not establish this change's success or x86_64/npm coverage.

## Consumers and maintenance

Codex/OpenCode use one generated preset selected by target platform and execution mode. Reasonix accepts directory-layout SKILL.md through its configured `.reasonix/skills`, `.agents/skills` or custom roots; the current installer uses `generic --target-skills DIR`, not an invented reasonix consumer. Kai's built-in System Packs use canonical snapshots with separate source locks and its own target transport; editing canonical skills does not update an installed snapshot automatically.

Current discovery uses optional composable capability descriptions and `resource-discovery: explicit`; referenced resources are loaded on demand. There is no primary-skill or helper-count policy and no mandated workflow. The model chooses its analysis and tools. Generated presets come from canonical sources. See agent-capability-milestones-20261126.md for the current responsibility boundary.

## Implementation and verification sequence

M1 contract → M2 package facts and persistent execution → M3 runtime selection/install/verify → M4 isolated dependency download/run/diagnostics → M5 preset generation and consumer verification. Each behavior change has a failing public-script or routing test committed separately before implementation. Test through command/environment boundaries with fixture tools; never use a real system package install as a unit test.

Real device validation is optional execution requiring a supplied target and authorization. Record untested architecture/libc/package-manager combinations explicitly. Do not store addresses, credentials or device-specific paths in skills or examples. No publication, deployment, existing Agent installation or global dependency configuration is part of this change.
