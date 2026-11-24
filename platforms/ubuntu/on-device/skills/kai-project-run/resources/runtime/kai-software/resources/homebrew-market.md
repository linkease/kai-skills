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

On a native local Mac session, prefer the market reader binding explicitly
provided by that host. Do not guess an Agent tool name. This reader supports detect,
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


Only when preparing or diagnosing a native operation, read
[ownership and failures](homebrew/operations.md). Only for private acceleration
component changes, read [private runtime](homebrew/private-runtime.md).
These operational references are not prerequisites for software queries.
