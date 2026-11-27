# Native bootstrap compatibility

Managed skill packages use the existing `zsetup checksum-tree` interface. The
Linux bootstrap lock selected 0.5.1 and the macOS lock selected 0.4.0; those releases
do not provide that interface. An installed legacy core was also reported ready.

The locks now select already published, byte-verified Linux 0.6.4 artifacts and
the signed macOS arm64 release 0.6.5. The macOS immutable directory is
`zsetup/macos/0.6.5/`. Readiness requires Linux 0.6.4 or desktop 0.6.5. Incompatible
externally managed executables remain unchanged and produce a conflict; the
first-dependency bootstrap still refuses to replace an existing core. No second
tree-digest implementation or automatic external-tool upgrade was added.

Validation: 21 bootstrap tests pass, including a regression covering the three
legacy platform configurations and preserved executable bytes. Generated
presets, independent packages and collection locks match canonical sources.
On native macOS arm64, the published 0.6.5 core and actual managed installer pass
preview, installation, upgrade, edited-file conflict preservation, uninstall and
unowned-file preservation. All native test files were isolated and removed.
This does not establish Windows native installer acceptance.

Coordination evidence remains outside this repository under
`build/verification/skills-p1-p6-20261127/` in the parent project. The frozen model
evaluation continues against its original source revision; this dependency fix
is prepared in a separate worktree.

## Embedded layout follow-up

The actual KaiPlus layout stores platform modules under `kaiplus-defaults/profiles/<platform>/skills` and common resources under `kaiplus-defaults/system-packs/common/skills`. Canonical-source and flattened-package paths do not cover this layout. Three new regressions fail before the fix: dependency resolution, executing the service query, and executing the storage observation. Sixteen existing shell/PowerShell entrypoints now also check the existing embedded common location, preserving their prior layouts and interfaces. No execution or diagnostic workflow is added.

The storage compatibility entry intentionally returns native filesystem observations; it does not select a home directory. KaiPlus content tests were still asserting path selection and mandatory `system-primary` routing. Those stale expectations fail on the unchanged baseline as well and are replaced by assertions that observations remain read-only and suggestions remain optional. Historical failure evidence is retained outside this source repository.
