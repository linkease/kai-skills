# WinGet metadata and payload acceleration

WinGet metadata and installer payloads use separate paths.

- Search and info use the registered native `winget` source directly. Prepared
  download/install reads only the installed Store-signed source `index.db`, then
  uses `ks-cli download --mode=auto` for the exact `versionData.mszyml` and
  manifest paths. Their SHA256 values must chain back to that signed index.
- Verified metadata is placed only in the command's isolated WinGet cache.
  Native WinGet still performs package and installer selection; no WinGet
  request is proxied.
- After native WinGet has selected an exact original HTTPS URL and official
  SHA256, `ks-cli winget download/install` sends that payload to the existing
  `ks-cli download --mode=auto` engine. The result must match the native SHA256,
  then native WinGet verifies and exports it before installation is allowed.

The reviewed workflow requires native Windows, WinGet `v1.29.380`, the registered
trusted official source, and explicit package identity, version and architecture:

```powershell
ks-cli --json winget download --id jqlang.jq --exact --version 1.8.2 --architecture x64 --source winget --download-directory 'D:/task/download' --accept-source-agreements --accept-package-agreements --disable-interactivity

ks-cli --json winget install --id PuTTY.PuTTY --exact --version 0.83.0.0 --architecture x64 --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity
```

Do not pass `--proxy` or `--no-proxy`; ks-cli rejects both and does not read
`KSPEEDER_WINGET_PROXY`. It does not change the Windows default proxy, trust store,
revocation policy or WinGet source registration.

For custom installer arguments, prefer native PowerShell with an argument array.
When invoking the native `ks-cli.exe` directly from Git Bash, MSYS can rewrite a
slash-prefixed value such as `--override '/quiet ...'` into a Git installation
path, even when shell-quoted. For that one native invocation use
`MSYS2_ARG_CONV_EXCL='*'` and explicit Windows paths for native path arguments;
do not export it globally or assume POSIX paths will still be converted. Verify
the arguments with `ks-cli --json --explain winget ...` before installation.
Keep the installer-specific silent flags, intended scope and existing user
configuration; a running installer process alone does not prove success.
After disabling conversion, preserve the installer's native Windows directory
syntax for directory overrides. Inspect installer logs for an MSI Error 1606
before classifying it as a network failure; download and signature success do
not validate an installer's `TargetDir` value.

The automatic download engine has bounded accelerated routes. WinGet metadata
requires the KSpeeder `/winget` route on both client and deployed upstream; a
client-only route whose upstream returns 404 is not acceleration. An unlisted vendor
uses its ordinary direct path. If direct access also fails, preparation returns
`WINGET_ORIGINAL_UNVERIFIED`; there is no WinGet proxy fallback. Add and validate
a real KSpeeder download route for that origin before claiming acceleration. The
JSON receipt records the selected route, strategy and
`acceleration_validation`. `selected=origin` means direct download and is not
acceleration evidence.

Package dependencies follow the same selection, auto-download, SHA256 and native
verification gates. Native acceptance must cover signed EXE, MSI and dependency
installation on the selected client/gateway version. Historical results from
another transport do not validate this no-CONNECT path; preserve pending or
failed native gates rather than inferring success from local adapter tests.
The receipt's `packages` describes prepared original payloads and their versions.
An install may reuse an older dependency that already satisfies the manifest;
preparing a newer dependency payload does not prove that version was installed.
Check the native registered versions and actual program use separately. Record
dependency reuse and first installation as different acceptance results.

Explicit official catalog recovery is available separately:

```powershell
ks-cli --json winget source update --name winget --disable-interactivity
```

This downloads the original official `source2.msix` through the same auto engine,
then uses native Windows package verification and same-identity deployment. It
can use direct transfer when no accelerated route is selected. It never
substitutes another source, disables signature checks or treats a transport hash
as publisher trust.

For a failed native `winget source update`, inspect its output and deployment
logs as well as the exit code. Native WinGet can print `Cancelled` and return
zero after a failed source deployment. That is not a successful refresh. If
downloads and trust validation succeeded but deployment reports `0x80070520`
(no such logon session), record a native deployment/session failure rather than
a download or CRL failure. Use the explicit ks-cli recovery above within the
authorized refresh operation, then verify its deployment receipt and a native
query. Distinguish a newer registered catalog from equal-version reuse; do not
reset sources, change trust or replace services to hide the native failure.

Windows CRL/OCSP and issuer retrieval remain independent native network requests.
Successful payload transfer, cached signature validation or catalog reuse does
not prove fresh revocation connectivity. Preserve these failures and diagnose the
certificate URLs without disabling validation.
