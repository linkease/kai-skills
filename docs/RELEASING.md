# Release and lifecycle contract

## Build

From a clean checkout, run:

```sh
sh tools/generate-platforms.sh
sh tools/verify-generated.sh
sh tools/build-release.sh release
```

The release directory contains one `.tar.gz` and one `.zip` for every catalog preset plus `release-manifest.json`. Builds are deterministic for the same checkout. The manifest records the source commit and sourceState, preset/version, archive SHA-256, and skill tree digest; every archive also contains the same information in `SOURCE.json`.

Publish only when `git diff --exit-code`, all CI contracts, and a second release build comparison pass. Attach the manifest and all archives to the same release. Do not publish archives made from different commits under one manifest.

## Install, upgrade, and uninstall

An extracted archive is self-contained:

```sh
sh linkease-skills-macos-remote-control-v1.0.0/install.sh --target /path/to/agent/skills
```

The installer stages a complete next destination and swaps it into place. It writes ownership state under `.linkease-skills/<preset-id>.json`, while preserving unrelated skills.

```sh
sh install.sh --target /path/to/agent/skills --upgrade
sh install.sh --target /path/to/agent/skills --uninstall
```

Upgrade and uninstall verify every owned skill against its installed digest first. If a user changed or removed one, the operation stops before the swap and preserves the destination. Resolve the conflict manually; never delete the ownership manifest to bypass review.

## Verification

For an archive listed in the release manifest:

1. Verify its `sha256:` value against the downloaded bytes.
2. Extract it and compare `SOURCE.json` with the release manifest.
3. Recompute the digest of the `skills/` tree before installation.
4. Use `--dry-run` and confirm that exactly one intended preset is selected.


Ten presets cover Ubuntu, Debian, iStoreOS, macOS and Windows in both modes. Four retired
iStoreOS primary IDs are migration aliases; their native interfaces ship as declared
non-SKILL resources. Ownership hashes protect resources as well as active skills.
A worktree candidate includes sourceDigest/treeDigest and sourceState=worktree; it is
reviewable but is not a published release or a clean-commit provenance claim.
Desktop offline completion does not imply native macOS/Windows acceptance.
