# Windows PKI auxiliary cache

Use this explicit bootstrap operation when native Windows reports an incomplete
chain or offline revocation while WinGet has a working explicit proxy. It does
not change a default proxy, import trusted roots or disable certificate checks.
ks-cli does not invoke Repair automatically.

The native entry is PowerShell 7.4+; Bash and the WinGet SDK are not required.
Select the existing target Transport. Keep the bundle, roots export and state on
private task storage, outside the repository. Export the target's existing roots:

```powershell
pwsh -NoProfile -File scripts/windows-pki.ps1 -Action Roots
```

Capture that JSON through the trusted Transport to a private controller file.
On a controller with working egress and Python with `cryptography >=40`, prepare
a new bundle. Use an existing project environment rather than installing Python
packages globally:

```bash
python scripts/prepare-windows-pki.py --roots target-roots.json \
  --host cdn.winget.microsoft.com --host github.com \
  --host release-assets.githubusercontent.com \
  --crl-url http://crl.sectigo.com/SectigoPublicServerAuthenticationCADVE36.crl \
  --output new-bundle.json
```

The hosts are explicit examples for the WinGet/jq acceptance path. Discover the
actual origin and redirect hosts for other software. The preparer retrieves the
current TLS leaf, follows AIA including PKCS#7 cross-sign candidates to the
target's existing roots, and retrieves current issuer-signed CRLs. An OCSP-only
issuer needs an explicitly supplied published CRL URL; unsupported paths fail.
It does not guess CRL endpoints, import a root, or claim arbitrary OCSP support.
The controller validates its TLS connections. PKI HTTP objects are authenticated
by signatures and native target validation, never by a newly generated checksum.
All inputs and downloads are bounded. Existing output files are preserved.

Transfer the original bundle through the trusted Transport, then on Windows:

```powershell
pwsh -NoProfile -File scripts/windows-pki.ps1 -Action Plan -Bundle D:/task/new-bundle.json -StateDirectory D:/task/pki-state
pwsh -NoProfile -File scripts/windows-pki.ps1 -Action Repair -Bundle D:/task/new-bundle.json -StateDirectory D:/task/pki-state
pwsh -NoProfile -File scripts/windows-pki.ps1 -Action Check -Bundle D:/task/new-bundle.json
pwsh -NoProfile -File scripts/windows-pki.ps1 -Action Restore -StateDirectory D:/task/pki-state
```

Plan checks full native SSL hostname and chain policy, including revocation for
every non-root certificate, using the existing roots and a memory store. It
creates no state directory. Every supplied CRL has its issuer signature and
time window independently checked, even if an older valid CRL is cached.
Unused intermediates, self-issued certificates and unrelated CRL signers are
rejected. The default minimum remaining validity is 300 seconds; use
`-MinimumValiditySeconds` for a stricter refresh window, up to 30 days.

Repair validates the whole bundle before opening the current-user CA store for
writing. It adds auxiliary certificates and CRLs alongside existing objects,
never replacing them. A durable intent journal and a per-repair property on each
new context establish ownership. Repeat Repair reuses matching objects. Fresh
material can be applied with the same state directory before expiration; earlier
owned versions remain recorded until Restore. CRLs must not be frozen into the
skills archive or used beyond their validity.

Restore requires matching ownership and exact object bytes. It preserves
conflicting/unrecognized contexts and reports failure. It can be repeated and
does not require an unexpired bundle. A released process lock can be reopened
after a crash; an active lock excludes concurrent mutations. Retain the state
directory while its objects are active. A failure attempts to remove only new
objects from that invocation, preserving objects owned before the invocation.

Check uses the current user's existing stores with no bundle objects added to
memory. Its `healthy` receipt is scoped to `current-user-capi-chain`, and
`nativeDownloaderValidated` remains false. In native testing, this check passed
while WinINet still failed online CRL/OCSP retrieval with 12057. Current-user CA
repair is therefore not a complete WinGet networking fix. Keep a separate native
download gate; do not expand into machine-store writes or a default proxy change
to turn a failed gate into success.

After Repair, test the original native command with the explicit ks-cli proxy.
Treat source refresh, metadata, installer download/hash, execution and actual
installation as separate gates. A certificate proof or Repair receipt alone is
not evidence that software installation succeeded.
