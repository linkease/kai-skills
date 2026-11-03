# Integrated execution

## Prerequisites

Read system release, architecture/libc, actual package database and tools with `check.sh`. Install the verified system/iStore-integrated package via package-manager. The inspected source calls it mise, but device feeds can differ or lack it. Verify `mise-exec`, `mise`, `/lib/functions/mise.sh`, the package owning them, and `uci -q get mise.main.runtime_dir`. Inspect its mount, free space and writable persistent storage. No upstream curl install and no manually exported HOME.

Read-only `check.sh` does not enter mise-exec: the system entrypoint can create a directory and perform network probes. It only lists installed versions if already in the correct HOME/shims environment. Entering an unconfigured integration can fall back to the original HOME; do not mistake that for persistent storage setup. Use the integration's UI/setup path for directory changes.

## Agent entrypoints and results

`probe.sh python|node|go RESOLVED_VERSION` establishes integration for this call and checks the exact installed SDK using verify.sh. Automatic SDK installation is disabled. Stdout is one JSON receipt; verification diagnostics go to stderr. Entering native mise-exec can run its existing setup/network probes; this is not the strictly read-only system check. Reuse authorization already granted for this execution environment, or explain those effects before a first entry.

Receipts have schemaVersion=1, operation, status and numeric exitCode. runtime-probe includes environment_validation, runtime_validation, home, effective mise directories, sdk_path and the exact version. A successful provenance check means the interpreter/SDK came from `mise where`, not merely a matching system version. runtime-install appends a JSON receipt after normal logs; it reports activation, phase and runtime_validation, with gateway_validation=not-applicable. Exit codes and failures remain authoritative. Invalid arguments or failures before entering the task program can return a diagnostic/nonzero status without an operation receipt; never infer success from a missing receipt.

For dependencies use the download skill's smoke entrypoint and result.json. It distinguishes runtime verification, real dependency execution and gateway evidence. Custom dependency.sh commands execute the requested tool; they still need application-specific runtime checks and download evidence before a complete acceptance claim. No general command interceptor is installed in Kai. Reading a system version is allowed as a system observation; it cannot establish mise SDK success/failure or replace an operation receipt.

## Interactive shell

Run `mise-exec`, then check HOME, PATH, `mise --version` and selected executable paths inside the resulting shell. Runtime dir is HOME, not a promise about cwd. `cd` to an explicitly chosen project directory for project configuration and dependencies. Exit returns to the original shell.

## Noninteractive local and remote Agent

Use `sh scripts/exec.sh /path/to/program.sh [literal-args...]`. It validates the configured directory and passes a serialized program to `mise-exec` stdin. The program runs in its shell; arguments are quoted without eval. Each separate invocation re-establishes the same integration. Agents such as Kai can export XDG_DATA_HOME/cache/config for their own state; those values must remain owned by the Agent. The updated system integration sets default MISE_DATA_DIR/cache/config from the configured runtime HOME. exec.sh supplies the same process defaults for older plugins, preserving explicit MISE_* overrides. Do not change HOME or the Agent XDG roots to repair mise storage. Check effective mise directories and exact runtime provenance; HOME/shims alone can hide this conflict. Never assume a previous Agent tool call changed the next tool call's shell.

For SSH use the existing strict host-key Target Transport. Send a complete target-side program that stages the execution helper and payload in a protected target temporary directory, runs `exec.sh` there, and cleans with a trap. Helper paths on the controller are not target paths. Classify a staged/installation run as apply; reuse its granted authorization. Do not send `mise-exec` in one SSH call and runtime commands in the next plain call. A persistent PTY also works if commands and their results remain in that same session.

When the Agent cannot stage files, send the complete payload directly as stdin to a remote `mise-exec` command after checking integration in a separate facts call; ensure the transport launches that command directly, not a shell that pre-reads the payload before handing off. No `mise-exec -c` or `mise-exec --` assumption. A LuCI-only transport without shell execution cannot run this workflow; explain the required execution capability.

Within the payload create/activate the venv or use `mise exec VERSION -- COMMAND`. Activation and cwd are shell state; repeat them in a later independent call. Keep payloads local to the target and avoid embedding credentials. Check command exit codes before reporting success.

Validate HOME and shims at the integrated entry boundary. After explicit Node/Go selection, mise exec may remove shims from PATH; this is expected, not a broken integration. dependency.sh checks the selected child's HOME, physical SDK bin directory and exact version instead. Python venv activation may prepend its bin directory while retaining shims. Do not reapply an entry-shell PATH rule inside a selected SDK child.

## Legacy acceleration environment

The inspected integration may inject `MISE_NODE_MIRROR_URL` and `MISE_NODE_VERIFY=0`. ks-cli inherits these. For a core Node command, in its scoped subshell unset that legacy mirror, set `MISE_NODE_VERIFY=1`, and inspect node.verify/mirror_url. A persisted mirror or disabled checksum/GPG setting needs diagnosis, not silent global changes. Preserve valid user settings and system HOME/PATH. ks-cli supplies final URL replacements/Go SDK mirror using actual installed ports; never copy default-port URLs from the old integration probe into new recipes.

`ks-cli doctor TOOL --json` is a read-only preflight; network tool execution itself may start an installed service, so include that effect in the authorization. Missing service/capabilities on OpenWrt route through verified system packages/iStore. `ks-cli service install/upgrade` is for the ordinary Linux lifecycle, not an OpenWrt package workaround.
