# Business distribution contract, version 1

The canonical skill IDs and `components/composition.json` remain the source of
platform inheritance and Transport selection. `components/business.json` declares
the business release version, explicit resource closures, program requirements,
business bundles and first-release architecture scope. It does not duplicate
platform preset membership.

`skills/<id>` is generated and independently usable. Its root SKILL.md has the
standard name/description contract. Original extended metadata is preserved in
the package metadata for Kai/Reasonix and is not a prerequisite for generic Agent
discovery. Private executable resources have no nested SKILL.md. Documentation
needed to execute an embedded resource is included locally.

`business-catalog.json` is a generated discovery view. The existing `catalog.json`
remains schemaVersion 1 with its existing preset fields, so existing readers are
not required to accept an incompatible schema. Bundle locks are generated from
the same declarations. Tests compare their member sets with the legacy presets.
Do not edit generated member lists as a second source of truth.

Each independent package records id, version, platforms, architecture scope,
program requirements, source resources and exact content digest. A common release
train starts at 1.1.0; this does not require separate Git repositories or a release
per skill. Bundle locks pin exact id/version/treeDigest rather than version ranges.

Read-only selection has exactly one root: skill, business bundle, or explicit
platform-all. Individual universal skills can be downloaded without knowing the
target. A remote execution plan requires the target platform, and platform-all
requires both platform and mode. Selecting a package never installs programs or
starts a gateway. Kai's own Transport excludes third-party Transport additions.

Inside one managed skills directory, one ID has one active version and digest.
Identical content can have multiple selection owners. A different version or a
different digest is a conflict until an explicit coherent upgrade updates every
affected selection. No implicit upgrades, downgrades or dependency range solver
are part of version 1. An unowned manually copied directory is preserved.

Ownership state records package content and selection intent separately. Removing
a selection only removes unchanged packages that have no remaining selection.
Old preset ownership is migrated by verifying its recorded files first; migration
does not overwrite modified files or infer ownership from matching names alone.

An embedded program dependency is a target requirement, not an Agent skill
dependency. Verified Bash/jq/mise/ks-cli discovery and explicit preparation keep
their original ownership and authorization behavior. Windows first entry is native
PowerShell; ordinary shell execution remains compatible Bash. WSL is its own Linux
target. WinGet has no CONNECT fallback.
