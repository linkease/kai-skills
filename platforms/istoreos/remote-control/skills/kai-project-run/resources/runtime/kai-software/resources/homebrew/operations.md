# Homebrew native plans

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


# Homebrew ownership and failure operations

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
The legacy Formula acceleration contract in ../brew-acceleration.md is separate;
it neither adds Cask support nor proves a released compatible Mac runtime.
