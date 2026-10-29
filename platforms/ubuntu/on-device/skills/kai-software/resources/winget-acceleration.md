# WinGet acceleration and native preparation

The registered official `winget` source remains intact. A fresh PowerShell MTA
worker loads the public Microsoft SDK, validates the source URL and actual package
version's catalog, and applies a process-scoped WinINet proxy on a non-null handle.
`ks-cli winget exec` supplies that local endpoint and relays CONNECT through an
explicit trusted KSpeeder endpoint. KSpeeder's existing authenticated admin CONNECT
handler is reused. The endpoint must have working egress; another process on the
same broken network is not guaranteed to solve a connection reset.

Origin TLS stays end to end. The worker preserves native source/manifest checks;
there is no certificate bypass, fake source field or display-table parser. This
is transport relaying, not plaintext content caching. The client reports actual
data tunnels and byte counts to stderr; metadata can also be served from cache.

Prepare SDK libraries in a task-owned directory:

```powershell
powershell.exe -NoProfile -File PRESET/skills/kai-tool-bootstrap/scripts/prepare-winget-sdk.ps1 -Action Plan -Destination D:/task/winget-sdk
powershell.exe -NoProfile -File PRESET/skills/kai-tool-bootstrap/scripts/prepare-winget-sdk.ps1 -Action Ensure -Destination D:/task/winget-sdk -Core D:/trusted/zsetup.exe
```

The current lock selects Microsoft.WinGet.Client 1.29.380 in-process native DLLs,
Microsoft.WindowsPackageManager.ComInterop 1.29.380 public projection and
Microsoft.Windows.SDK.NET.Ref 10.0.26100.87 managed dependencies. Every package
and extracted file has a reviewed SHA256/size. zsetup >=0.4.0 owns downloading and
verification; extraction uses only the five locked entries and bounded sizes.
Existing conflicting SDK directories are preserved, and preparation stages are
removed on failure. No PowerShell module, .NET SDK or system package is installed.

If upstream package TLS fails, use the explicit `-PackageCache DIRECTORY`. It must
contain the original pinned packages named `ID.VERSION.nupkg`, obtained through a
trusted Transport. They are copied into private staging and still verified by
zsetup before extraction. The three package URLs and SHA/size are in
`winget-sdk.lock.json`; there is no runtime checksum override. SDK.NET binaries are
dependencies, not software provenance evidence. Keep the original packages and
their license/notice files in the cache. The desktop cold-download gate must be
reported separately from cached preparation.

In Git Bash, set task-scoped variables:

```bash
export KAI_WINGET_ACCELERATION=required
export KAI_KSCLI_BIN='D:/task/ks-cli.exe'
export KAI_WINGET_SDK_DIR='D:/task/winget-sdk'
# Set KSPEEDER_WINGET_PROXY privately to the trusted endpoint; never commit it.
bash PRESET/skills/kai-software/scripts/software.sh info winget:Git.Git
bash PRESET/skills/kai-software/scripts/software.sh search PowerShell
```

For remote HTTP CONNECT endpoints use a trusted tunnel to numeric loopback; direct
remote endpoints require HTTPS. Upstream credentials stay in the caller's private
environment. The child only receives the ephemeral loopback endpoint in that
variable. Explain is read-only and redacts endpoint credentials:

```bash
ks-cli --json --explain winget exec -- pwsh.exe -MTA -File WORKER.ps1
```

The current accelerated Kai adapter validates search/info only. Install/remove,
source refresh and additional architectures need separate native acceptance.
`ks-cli winget NATIVE_ARGS` can pass the native CLI an explicit proxy, but a machine
may disable that option. Such a policy failure is preserved, never auto-enabled.
Do not silently route mutation operations through a different unverified adapter.

For native CLI queries and installer downloads, WinGet must allow its explicit
proxy option. Within the user's authorization, enable it once using:

```powershell
winget settings --enable ProxyCommandLineOptions
```

This permits per-command proxy arguments; it does not set a Windows or WinGet
default proxy. ks-cli still requires the private `KSPEEDER_WINGET_PROXY` endpoint
on each invocation and does not enable the option itself. Preserve administrative
or Group Policy failures. Then run, for example:

```powershell
ks-cli winget show --id Microsoft.PowerShell --exact --source winget --accept-source-agreements --disable-interactivity
ks-cli winget download --id jqlang.jq --exact --source winget --version 1.8.2 --architecture x64 --download-directory 'D:/task/download 中文' --accept-source-agreements --accept-package-agreements --disable-interactivity
```

Use the SDK path for structured package records. The reviewed ks-cli native
preparation candidate accepts WinGet `v1.29.380` and the registered trusted
official source only. `download`/`install` require `--id`, `--exact`, `--version`
and `--architecture`; unknown versions and unsupported flags fail explicitly.
Read the owning ks-cli `docs/winget-connect.md` and current native verification
evidence before using a locally built candidate; a source change is not proof
that the downloadable release contains it.

Native WinGet selects the original HTTPS URL and SHA256 in an isolated command
workspace. ks-cli first calls its existing automatic download engine. Its origin
routes are bounded: an unlisted vendor can fall back to Windows direct access,
which may still reset. If automatic acquisition fails, this adapter uses the
explicit trusted CONNECT endpoint to fetch the same original HTTPS URL. It labels
that outcome `trusted_connect / auto-then-connect-fallback`, without claiming a
cached or raced transfer. SHA256 and subsequent native WinGet validation remain
mandatory before export or native installation. Package dependencies are prepared
first; successful download alone does not establish actual install acceptance.

The JSON preparation receipt reports `catalog_refresh` independently:
`failed-native-cache-used` means refresh failed but native metadata was usable;
`not-independently-verified` does not assert freshness. If complete native metadata
cannot be obtained, stop before automatic payload download and installation.
Repair the source's network access and explicitly retry or refresh with its
original manager. The reviewed native packaged-Windows CLI candidate also provides
`ks-cli --json winget source update --name winget --disable-interactivity`:
it fetches the original official source2.msix through auto/CONNECT, then uses native
PowerShell 5.1/Appx to deploy only a newer, same-identity Microsoft Store package.
An equal version reuses the existing native signed package; check `deployment`
and both version fields rather than inferring a new deployment. It preserves the
registered source URL/type/trust and rejects downgrade, unsigned/forced deployment
and unsupported unpackaged contexts. A transport hash alone is not signature
evidence. Source update remains an explicit write, never an installation side
effect. Native `source update` returning 0 with `Cancelled` is not refresh success.
Do not fabricate a manifest URL/hash, rewrite source identity,
or substitute an unreviewed downloaded catalog. A successful CONNECT preflight
does not guarantee all native source-refresh/version-check requests use it.

An installer can make its own network requests outside the WinGet proxy. See the official
[proxy design](https://github.com/microsoft/winget-cli/blob/master/doc/specs/%23190%20-%20Proxy%20Support.md)
and [download command](https://learn.microsoft.com/en-us/windows/package-manager/winget/download).

Keep certificate-chain retrieval as a separate acceptance gate. Error
`0x80072f19` is WinINet's certificate revocation check failure (12057); a working
CONNECT tunnel alone does not prove Windows can retrieve issuer certificates,
CRLs or OCSP responses. Use native certificate diagnostics to identify the failed
URLs and preserve certificate validation. `certutil -verify -urlfetch` can exit 0
while reporting `CRYPT_E_REVOCATION_OFFLINE`, an incomplete chain or unknown
revocation status; inspect those results before claiming validation passed.
Cryptnet/CAPI certificate retrieval is independent of package transfer and cannot
be assumed to inherit WinGet's per-session proxy. The current CONNECT relay also
does not provide an ordinary HTTP GET/OCSP POST proxy. Diagnose direct access and
the exact certificate URLs separately; neither an HTTP probe nor a valid cached
signature result identifies the resetting network device or proves fresh online
revocation is healthy. Preserve the Windows default proxy and trust/revocation
policy.

Native acceptance on AMD64 established PuTTY MSI/Python EXE download, signatures,
installation, execution and owned removal. The complete dependency workflow is
still blocked at VC++ original acquisition after three implementation rounds.
Do not enable the accelerated SDK helper's install/remove branch or claim general
WinGet dependency/install coverage from these individual native successes.
