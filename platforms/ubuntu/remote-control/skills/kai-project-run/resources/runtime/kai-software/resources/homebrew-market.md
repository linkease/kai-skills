# macOS Homebrew market Provider

This is the native KAIPlus contract, separate from the Formula-only
`software.sh` / `software-task/v1` route and unreleased ks-cli Cask candidates.
Do not invent a ks-cli Cask command. No Homebrew or client is installed by this
client script. Resolve execution on the selected target through its Transport.

A native Mac KAIPlus TCP server supplies absolute `KAI_SOFTWARE_CLI_BIN` and its
selected-target loopback `KAI_SOFTWARE_API` to local session processes. Other
transports need their own target-side contract. Missing variables, old CLI,
non-Mac target, remote endpoint, unsupported action or unavailable Provider block
explicitly. Never guess port 8198 or run the controller's Provider instead.

## Read-only KAI conversations

On a native local Mac KAIPlus session, prefer `use_capability` with
`capability_id: "tool:software_market"`. This host-bound reader supports detect,
search, info, installed, outdated, sources, files, verify and tasks. Pass the
exact package id or operationId. It accepts no endpoint, Shell, install, apply,
confirmation or cancellation operation. Remote targets never receive the local
controller's reader. Do not call the mixed read/write skill workflow or fall
back to Bash just to query the market from a diagnostic-only conversation.

After explicit package selection, `action: "preview"` with the typed local
install/upgrade/uninstall request returns a real native plan preview and
`reviewPath`. It stores no plan/operation and contains no confirmation token.
Give the link to the user. Opening it rechecks current facts and saves a fresh
formal plan in the software page; changed fingerprints are explained and risk
confirmation is still required. The model cannot confirm or apply it. Diagnosis
uses tasks/installed first; do not preview a repair until the user selects it.
The CLI below remains available to authorized host workflows; it is not a way
to bypass the read-only conversation boundary.

## Read first

```sh
bash scripts/homebrew-market.sh detect
bash scripts/homebrew-market.sh search --query 'window management' --kind cask
bash scripts/homebrew-market.sh info --id brew-cask:homebrew/cask/rectangle
bash scripts/homebrew-market.sh installed
bash scripts/homebrew-market.sh outdated
bash scripts/homebrew-market.sh sources
bash scripts/homebrew-market.sh files --id brew:homebrew/core/tree
bash scripts/homebrew-market.sh verify --id brew:homebrew/core/tree
```

Ordinary queries do not create AI sessions. Catalog is a local index; Inventory
is native state. Keep full `brew:TAP/TOKEN` and `brew-cask:TAP/TOKEN`; same names
never merge. Legacy `brew:NAME` is only resolved by native Formula info; persistent
plans contain full identity. An unavailable inventory is not a zero-app result.
Other-source app bundles remain read-only and are not adopted or overwritten.

After explicit selection, create one typed plan on stdin, for example:

```sh
printf '%s\n' '{"targetId":"local","action":"install","packageIds":["brew-cask:homebrew/cask/rectangle"],"policy":"none"}' | bash scripts/homebrew-market.sh plan
```

Return the resulting `reviewPath` as a link in KAIPlus. It opens the existing
software surface and loads the persisted plan for human review. Creating a plan
never installs packages. The CLI does not output the confirmation token and does
not provide apply, confirm or cancellation. Do not reconstruct those calls in
Shell to bypass review. User confirmation in the software page enqueues the
same Provider that owns native execution, cancellation, Inventory and Receipt.

Actions: bootstrap, install, upgrade, uninstall, refresh, source-add,
source-remove, source-trust, source-untrust. Package actions take 1–16 exact packageIds;
source actions take full owner/tap and an optional credential-free HTTPS Git
sourceUrl. Source trust and its revocation are separate explicit plans. No arbitrary commands,
force, checksum bypass or signature bypass. Plans expire after 15 minutes and
bind target, Prefix, architecture, version, metadata and source state. Changed
facts require a new plan and confirmation. Homebrew controls native dependency
resolution, scripts and install locations; show the returned dependencies,
effects, risks and caveats.

Upgrade respects native exclusions; includeAutoUpdates=true requires explicit
review for self-updating apps. Uninstall defaults zap=false. Explicit zap=true
may delete user data and files shared by apps. Native Cask login-item hooks may
require macOS Automation consent: sudo success does not grant TCC. Retain native
warnings even when Inventory accepts removal; do not claim registration or user
data was completely cleaned. Do not patch the TCC database or skip native hooks.

## Setup and ownership

Bootstrap is its own typed plan, not a temporary hidden install command. The
owner locks the official installer revision/SHA256, checks CLT, architecture,
Prefix, authorization and existing installs, then verifies native Formula/Cask
access. Existing user Homebrew retains its ownership. Only a prior owned partial
install with matching prefix identity may be resumed; no adoption or recursive
shared-prefix cleanup. Apple Silicon can first-install. Intel only verifies and
manages existing Homebrew; absent Intel is blocked by the accepted support
policy. CLI query success or Formula-only support never means full market ready.

## Failure and acceleration

Read `tasks --id OPERATION_ID` for the persisted route, stage, category, exit
code, redacted logs and Receipt. Same-Prefix mutations serialize. Cancellation
kills managed work and rechecks Inventory; partial changes may remain. Restart
observes rather than replaying an interrupted mutation. Only diagnose on failure;
repair requires another typed plan and human confirmation. Never silently retry,
change Provider or assume exit 0 proves functionality. Inventory/artifact checks
and a meaningful application use test are distinct evidence.

Default native market policy is none: native configuration/cache, no acceleration
claim. Read the selected device's supportedPolicies; a verified private release
must explicitly contract lease-v1 before auto can be offered. Required also needs
the reviewed per-download guard contract for this Homebrew source, platform,
trusted product helper and every selected/dependency Bottle. Missing pins, incompatible versions, ownership/integrity failures and uncontracted
policies block before mutation. API, Bottle,
Cask artifact and Tap Git require separate actual transfer receipts and normal
authorization/checks. An API doctor result does not prove artifacts accelerated.
The legacy Formula acceleration contract in brew-acceleration.md is separate;
it neither adds Cask support nor proves a released compatible Mac runtime.

## Optional private acceleration components

The native Provider exposes read-only `acceleration` observations, including the
product-private owner snapshot. A component file match is not a running service,
a transfer receipt or permission to enable an acceleration policy. A reviewed
Darwin release pin must be supplied by the product distribution; when absent,
setup is unavailable. Never substitute a latest download, candidate source build
or temporary installation script.

If explicitly requested, `action: "acceleration-setup"`, `targetId: "local"`,
`policy: "none"` creates a typed setup/verification plan when the trusted pin is
available. The same software confirmation UI and Provider queue apply. The plan
shows immutable sources, archive digest, architecture, UID and private destination.
There is no arbitrary URL, file path or Shell option in the request. This does
not take over external clients, alter Homebrew/shell files or install/start a
persistent service. Unowned directories, external installations needing
verification, mismatched builds and unreviewed interrupted staging block the operation.

Its Receipt includes native version checks, owner inventory and original route.
Cancellation/restart observes owned files without replay. Diagnosis remains
read-only. A marked private installation retaining its verified archive can
produce a fresh acceleration-setup recovery plan for missing files only. Review
the exact missing-file list; confirmation rechecks directory/file identity,
extracts from that owned archive and links only absent files. Existing files
are never replaced and no archive is redownloaded. Changed payloads, unknown
files, missing ownership/archive, unverified external installations and unmarked or unverified historical staging
remain blocked; never blanket-remove a user directory or replay an old setup
confirmation. API and core Bottle candidate probes do not enable
Cask Artifact or Tap Git acceleration. Homebrew API fallback is independent of
`HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK`; do not call the generic brew wrapper a
required-policy contract. Product auto/required use the native Provider's typed
plan and operation-owned lease, not a model-issued runtime or Shell command.

For a contracted install/upgrade, plan metadata and execution use the same owned
gateway route. The native Bottle domain remains the official OCI root; the
operation-local ARTIFACT_DOMAIN routes downloads through the owned gateway.
Never replace the Bottle root with a flat gateway URL. The full original native
metadata fingerprint remains strict, including source, version and checksums. Read-only plan preparation may start an already verified private
foreground runtime; it installs no software. Apply still requires the exact
plan confirmation. The operation retains its runtime until native Inventory
reconciliation, including cancellation, then closes the owner control stream and
retains the durable runtime/cleanup receipt. Lost runtime never permits replay.

Required controls directory and declared payload downloads, not every network
operation of the Homebrew process tree. A private task downloader-selection cache
binds the truthful native curl selection; each curl request is confined to the
operation gateway and recorded. The parent Homebrew retains its native extraction
sandbox. Never fake curl versions, patch native Homebrew, weaken its protection,
or silently substitute auto/none. Unknown native builds and uncovered Cask,
Tap, source downloads, custom pour conditions and installation hooks block at
plan time. Core Formula Bottles must match the exact OCI repository, native tag,
Cellar and SHA256. Declared Bottles are fetched and verified before installation;
apply rechecks the complete metadata and the guard contract. Receipt retains
native downloader selection, per-request results and matched artifact hashes.
Before gateway setup, probe only native binary/Prefix identity; full Cask
readiness and selected metadata are read on the owned gateway route. Required
uses API definitions and clears inherited no-API bootstrap flags only for this
command. A Bottle does not authorize Git or custom source fallback strategies;
these selections block before writes. Cancellation tracks descendants that
create another process group/session, rechecks process ownership and preserves
cleanup failures as warnings. It still performs native Inventory reconciliation
on the original route before closing the runtime. Native inventory may fetch missing metadata;
HOMEBREW_NO_INSTALL_FROM_API is not an offline inventory switch and must not be
added to avoid those reads. Gateway loss must report unavailable without native
fallback. KSpeeder internally may choose origin/direct or proxy. Internal origin,
cache and proxy decisions remain unreported until actual decision evidence is
available; gateway transit alone must not be called accelerated. The candidate
required download probe covers core Formula API/Bottle paths, not Cask
artifacts, Tap Git or direct source/hook networks. Reject unsupported selections
before native writes. Native TLS, JWS, signatures and Hash checks stay enabled.
Auto prefers supported gateway paths and explicitly permits native fallback;
Cask artifacts/Tap Git are not claimed accelerated. A runtime startup/integrity
failure stops before writes; no write is automatically retried through another
route. The UI must preserve an explicitly selected policy instead of replacing
required with none. Source/build candidates are still not published releases.


### Interrupted private-runtime commits

A staging name alone grants no authority. A new acceleration-setup plan may
recover exactly one private interrupted stage only when its owner marker,
complete retained archive, configured release digest and every present payload
match. Inspect binds directory/file identities and hashes, and separately binds
an absent destination or an already marked compatible partial destination.
Planning is read-only; it never replays the old operation or starts a service.
After explicit confirmation in the shared Provider queue, recover only reviewed
missing files from that archive, with native version checks and no download or
replacement. Recheck inventory before commit. Move the original stage into a
new private retained-history container, preserving its contents without deletion;
Receipt records the retained path. Cancellation or failure may leave a complete
destination plus the interrupted stage: observe first and create another plan
for retention only. Never infer absence of partial effects from process exit.
Unknown/unmarked stages, multiple stages, modified payloads, unknown files,
symlinks, broad permissions and unmarked destinations (even empty) remain blocked.
Do not delete them, adopt external runtimes, or infer a published release pin.
Retained history is not automatically pruned and does not prove acceleration.


### Verified external component reuse

Known external directories can supply read-only components only when a complete archive matches the configured product release pin and every native payload and identity matches. Require the reviewed lease-v1 contract. Reject group/other writable files or directories, symlinks, missing archives, changed files and ambiguous sources. Inspection and planning never execute candidates. A new acceleration-setup plan names the exact source and effects; explicit confirmation permits native version checks and saves a private reuse reference. Never copy, reinstall, overwrite or take ownership of external files. Each operation has an owned temporary lease and private workspace/Receipt. Existing external services are not attached, changed or stopped. Recheck source identity, digests and the reference before execution. Changed identity requires fresh review; a missing reviewed source never silently selects another. A simultaneous private install and external reference blocks. No formal pin means no executable reuse/setup route. This component contract is not general existing-service reuse or proof of acceleration.
