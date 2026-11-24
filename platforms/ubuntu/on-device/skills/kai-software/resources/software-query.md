# Software query contract

`query-entry.sh search|detail|inspect REQUEST.json` or native Windows
`query-entry.ps1 -Operation ACTION -RequestFile REQUEST.json` runs through the
selected target Transport. Set ZSETUP_TASK_TARGET_ID from trusted target metadata;
without it only `local` is accepted. No query bootstraps tools or refreshes indexes.

Requests: targetId plus query (search), id (detail), or software (inspect).
Optional provider and limit (1–10, default 3). Source-qualified identities retain
all components: apt:NAME, opkg:NAME, apk:NAME, istore:NAME, scoop:BUCKET/APP,
winget:VENDOR.APP, brew:TAP/TOKEN, brew-cask:TAP/TOKEN,
docker-image:IMAGE_ID, docker-container:CONTAINER_ID.

Unix adapters reuse native package caches and the existing iStore search.
Windows uses existing native Scoop/WinGet readers without requiring Bash/jq;
unknown/native provider failures are explicit, not empty inventories.
Brew uses existing native Formula/Cask metadata, without auto-update.
Docker supports only an explicitly local Unix engine: local image and container
facts, no registry search or inferred update candidate. Unsupported targets or
providers return blocked; use another available capability when needed.

Response: protocol software-query/v1, schemaVersion, action, targetId, status,
items, limit, hasMore, reason, nativeExitCode (when reported) and effects. IDs, source, kind, version evidence
remain separate. Search/default output is not proof of installation. Unknown
runtime/candidate remains unknown; cache absence is not an online version claim.
Descriptions have 240-character bounds and the complete JSON has an 8192-byte
bound. Oversized identities/evidence fail explicitly, never truncate JSON.
Only the selected records are projected; provider manifests and arbitrary
native diagnostics are private. All queries have effects: [].

Plan/apply/backup use the original software-task/v1 contract and do not consume
query projections as execution plans. Approval, device protection, cancellation
and whole-task decisions remain with the existing host and Agent.
