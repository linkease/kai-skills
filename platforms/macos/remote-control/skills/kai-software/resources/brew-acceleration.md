# Homebrew query and installation acceleration

Keep the selected source identity `brew:FORMULA`. By default the helper runs
native Homebrew. With `KAI_SOFTWARE_ACCELERATION=required`, search, info,
installation and explicit refresh first run `ks-cli doctor brew --json`, then
the formal `ks-cli brew` operation. Missing client or readiness is a failure;
there is no silent native fallback under required policy. Removal and local
file inventory retain their original native owner. The helper installs no
client, module or service as part of this selection.

Use a compatible client containing the process-local Homebrew routing fix and
Homebrew >=5.0.0. That client creates a temporary `HOMEBREW_CURLRC` for the
negotiated HTTPS gateway alias/port and includes an explicit absolute caller
curl configuration without changing it. It removes its temporary file when
the command exits. A legacy boolean curl setting retains its native lookup;
the caller remains responsible for DNS in that explicitly selected case.
No hosts file, system DNS, default proxy, certificate or revocation setting
changes. Host/SNI, Homebrew's signed API metadata and bottle checks remain.

Example, on the selected Mac through its authorized Transport:

```sh
KAI_KSCLI_BIN=/path/to/trusted/ks-cli KAI_SOFTWARE_ACCELERATION=required \
  bash scripts/software.sh info brew:tree
```

Inspect the source, current version and existing installation before a change.
Keep existing user applications. API acceleration alone does not establish
bottle or Git tap acceleration; record the actual route and native result.
For a bottle install whose official `ghcr.io` route is unavailable, explicitly
select the existing KSpeeder `brew-env --mode=plus` artifact setting:
`HOMEBREW_ARTIFACT_DOMAIN=https://ghcr.linkease.net:PORT`, using the negotiated
gateway port. A compatible client also resolves that explicitly selected alias
inside its temporary curl configuration. Preserve registry authorization and
the original bottle SHA256. The gateway must already have an authorized Plus
session for its GHCR route; a local HTTP 403 is an authorization failure, not a
DNS failure. Preserve it and have the user establish that session through the
normal account flow before retrying; do not copy another service's credentials
or bypass the gate. Native Homebrew can subsequently fall back to `ghcr.io`,
so retain the first gateway error as well as the final native download error.
That registry alias does not establish support for
arbitrary source-archive URLs or Git tap operations.
`ks-cli doctor brew` checks the API gateway contract, not the caller-selected
GHCR route's Plus session or a complete bottle transfer. Before retrying a bottle
install through that route, check its gate on the selected target with an
existing trusted curl and the same gateway port:

```sh
brew_gateway_port="${KSPEEDER_PORT:-5443}"
curl --noproxy '*' --fail --silent --show-error \
  --connect-timeout 5 --max-time 15 \
  --resolve "ghcr.linkease.net:${brew_gateway_port}:127.0.0.1" \
  "https://ghcr.linkease.net:${brew_gateway_port}/v2/"
```

A 403 from the Plus gate requires a normal authorized session before another
installation attempt. A 200 establishes only that this gate is open; still
verify the manifest, blob, original hash, installation and actual program use.
Do not substitute the generic `/homebrew-bottles` DomainFold route to work around
the existing GHCR entitlement rule. Keep API-only acceleration and explicitly
selected Plus bottle acceleration separate in the result. Match the target's
current Homebrew version when diagnosing fallback; do not carry an old DNS
diagnosis forward without a current probe.
The new client is a locally validated candidate until its release provenance
is published. A failed original API/JWS/bottle check remains a failure.
