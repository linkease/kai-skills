# WinGet payload acceleration

WinGet metadata and installer payloads use separate paths.

- Search, package selection and manifest lookup use the registered native
  `winget` source directly. ks-cli does not proxy this traffic. If the catalog is
  unreachable or incomplete, stop before downloading or installing anything.
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

The automatic download engine has bounded accelerated routes. An unlisted vendor
uses its ordinary direct path. If direct access also fails, preparation returns
`WINGET_ORIGINAL_UNVERIFIED`; there is no WinGet proxy fallback. Add and validate
a real KSpeeder download route for that origin before claiming acceleration. The
JSON receipt records the selected route, strategy and
`acceleration_validation`. `selected=origin` means direct download and is not
acceleration evidence.

Package dependencies follow the same selection, auto-download, SHA256 and native
verification gates. The current native acceptance covers individual signed EXE
and MSI installations; a general branching dependency graph remains unaccepted.

Explicit official catalog recovery is available separately:

```powershell
ks-cli --json winget source update --name winget --disable-interactivity
```

This downloads the original official `source2.msix` through the same auto engine,
then uses native Windows package verification and same-identity deployment. It
can use direct transfer when no accelerated route is selected. It never
substitutes another source, disables signature checks or treats a transport hash
as publisher trust.

Windows CRL/OCSP and issuer retrieval remain independent native network requests.
Successful payload transfer, cached signature validation or catalog reuse does
not prove fresh revocation connectivity. Preserve these failures and diagnose the
certificate URLs without disabling validation.
