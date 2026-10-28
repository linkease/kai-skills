# Desktop execution contract

macOS and Windows share the common software, SDK, project dependency, usage and
acceleration capabilities. Native service management stays in its System Pack:
launchd on macOS and the Windows service/eventlog APIs on Windows. The controller
operating system never determines the target's package manager.

Windows shared scripts run in a verified Git Bash/MSYS Bash. WSL launchers are
rejected before execution. The PowerShell bootstrap can locate an existing Bash
or explicitly install Git.Git from the winget source; installer output goes to
stderr and the result is one structured receipt. Original installer failures are
retained. Every independent shell invocation selects its own environment.

Structured software queries default to the existing `Microsoft.WinGet.Client` module
with the explicit `winget` source. An explicit required acceleration path uses the
source-locked official in-process SDK through `ks-cli winget exec`; the current
candidate supports search/info, a prepared X64 SDK and PowerShell 7.5+.
No localized display-table parsing or implicit
module installation is used. Exact IDs and versions are checked before and after
installation. A missing module is `native-adapter-unavailable`; missing verified
client artifacts remain unavailable even when a different platform has a release.
This does not assert that an upstream project has no desktop release.

Native executable plans retain argv as data. An explicit `shell=cmd` plan accepts
batch programs with bounded literal arguments, uses `/d /v:off /s /c`, and rejects
cmd expansion/control characters. Such characters require a native executable
entry. In particular, npm uses the selected Node SDK's `node.exe` and its own
`node_modules/npm/bin/npm-cli.js`, and pip uses project `Scripts/python.exe -m pip`.
Their acceleration environment comes from a passing Doctor and the current
client's validated read-only Explain protocol. This is a native invocation of the
existing route plan, not proof of gateway traversal by itself.

Convert known script/SDK paths explicitly before native execution. The MSYS
argument conversion override belongs to the native child. Docker mount and
container POSIX paths retain their protocol meaning; unrelated child processes
retain the caller's conversion setting. A drive path, backslash, Unicode text,
space, empty argument or shell-looking literal must never become generated code.

Offline validation runs the real PowerShell parser and executes scripts against
external command/module protocol fixtures. The signed GNU Bash 3.2 source is
compiled locally and used for canonical script syntax and shared behavior checks.
Tool provenance is in `tests/multisystem/desktop-tools.lock.json`. To repeat the
desktop contracts, supply `KAI_DESKTOP_PWSH` and `KAI_DESKTOP_BASH32` as absolute
paths to verified local tools and run `tools/test-multisystem.sh --milestone MS9`.

These offline tests establish adapter and protocol behavior. Linux PowerShell 7
parsing, Linux-hosted fixtures, cross compilation and compatibility tools do not
count as native desktop passes.

On 2026-10-28 the user authorized native macOS arm64 and Windows x64 SSH testing.
The [three-round native follow-up](../verification/desktop-optimization-20261028.md)
records successful paths and unresolved gates separately, retaining the first
native report as history. Frozen Python/Node/Go/uv installation and real
pip/npm/Go/uv projects passed on both native targets. WinGet catalog APIs still
block or return unverifiable source/version data after explicit source refresh.
The [subsequent residual repair](../verification/desktop-followup-20261028.md)
fixes the owner PS5 Bash argv bridge and rejects null/blank WinGet versions before
source reads. Native logs show official CDN connection resets; the final software
entry returns catalog-unavailable, without proving a successful online query.
The [KSpeeder acceleration follow-up](../verification/winget-acceleration-20261028.md)
then passed actual official-source queries through an authenticated CONNECT
endpoint. Source TLS and actual catalog/version checks remain active; no global
proxy was changed. The user subsequently authorized WinGet's own explicit proxy
option; the [native CLI follow-up](../verification/winget-cli-20261028.md) records
its activation, CLI query results and separate download/certificate-chain gates.
The complete desktop release verdict remains partial. Other desktop architectures
still require native runners.

The subsequent [Windows PKI diagnosis](../verification/windows-pki-20261028.md)
proved both origin certificate chains with native SSL hostname and full revocation
checks using existing roots plus memory-only intermediates and signed CRLs.
Persistent current-user CA cache repair is a separate proposed bootstrap operation;
it has not yet established native WinGet download or installation acceptance.
The [implementation follow-up](../verification/windows-pki-implementation-20261028.md)
delivers explicit preparation, Plan/Repair/Restore and current-store Check with
native lifecycle/ownership tests. WinINet still fails online CRL/OCSP retrieval
after current-user CAPI succeeds. Check receipts explicitly scope their result;
the native download gate remains failed and the test's additions were restored.

An explicitly isolated Windows mise root excludes inherited foreign mise shims
from its child PATH. Versioned Python entries inside a linked framework retain
their real prefix and undergo the original version/provenance checks. Windows
SSH supervision owns the child tree through a job assigned before execution.
The client may use an ephemeral CONNECT relay for local package gateways; TLS
remains in the native tool, existing proxies take priority, and machine proxy/DNS
configuration is preserved. These client changes are source candidates, not a
claim that desktop one-click client installation or production rollout is complete.

The [Windows tool follow-up](../verification/windows-tools-20261028.md) closes the
missing Windows x64 mise bootstrap provider. Native zsetup verifies the frozen
official ZIP, and both mise.exe and mise-shim.exe retain an ownership receipt.
The public Git Bash entry validates both files before executing an owned install.
Native PS5 install, PS7 reuse and the final preset lifecycle passed with a trusted
original archive cache. Direct origin TLS still fails on that target and is kept
separate from those passes. The user deferred the prior WinGet revocation issue;
the complete desktop release verdict remains partial. macOS arm64's recorded
functional scope is complete, with no claim for other native architectures.

The [mise acceleration follow-up](../verification/windows-mise-acceleration-20261028.md)
then passed Windows online bootstrap through existing ks-cli auto selection,
without an ArchiveCache input. New mise installed and ran Node; native npm
metadata, installation and project assertions passed. The generic file helper
also defaults to auto and retains origin-probe byte counts. Four same-window
proofs confirmed the tested gateway paths with original integrity checks.
Windows ran the client and accessed an isolated remote gateway through the
trusted Transport; no local KSpeeder service or default proxy was installed.
Native npm audit POST requests returned 405 and remain an explicit limitation.
