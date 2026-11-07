# Scoop provider

Scoop identities are always `scoop:BUCKET/APP`; catalog refresh uses
`scoop:BUCKET`. Never pass these identities to WinGet. Search may aggregate Scoop
and WinGet rows, but source-qualified rows remain distinct even when their names
match.

The provider accepts only the zsetup M6 ownership receipt locked in
`scoop.lock.json`. A missing or mismatched installation is repaired only through
the formal `zsetup install scoop --foreground -- ...` application entry. It is
never installed through WinGet or the public Scoop bootstrap script.

`KAI_SOFTWARE_ACCELERATION=required|auto|none` is passed unchanged to ks-cli.
For an ephemeral required-mode runtime, set both
`KAI_KSPEEDER_RUNTIME_BINARY` and `KAI_KSPEEDER_RUNTIME_IDENTITY`; setting only
one is invalid. A required operation succeeds only when every payload receipt is
hash-verified and selected through `admin_proxy`.

The adapter leaves dependency resolution, extraction, shims, persist and scripts
to native Scoop. ks-cli's postconditions and the adapter's receipt/state checks
must both pass. Bucket refresh uses ks-cli's process-local Git rewrite and does
not alter the stored remote URL or global Git configuration.
