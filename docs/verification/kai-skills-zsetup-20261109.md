# kai-skills zsetup distribution M0–M12 execution

Date: 2026-11-09

## Result

M0–M10 passed. The public channel now uses zsetup `0.6.4` and kai-skills
`1.2.4`. Installation does not require Git, npm/npx, ks-cli or kspeeder. The
target runtime is POSIX shell, jq (including the OpenWrt build without
Oniguruma), and zsetup. Archive extraction, file/tree SHA-256 and bounded
downloads are provided by zsetup.

M11 added the version-free public `setup.sh` channel. On a target without
zsetup, the initial bootstrap needs POSIX shell and curl or wget; it caches
zsetup below the user's data directory and then hands every remaining network,
integrity and archive operation to zsetup. The channel does not modify shell
profiles and does not carry `KAI_SKILLS_REQUESTED_RELEASE`.

M12 made that channel progressive: the normal input is now one skill id or
`all`. It defaults to Codex-compatible user skills at `~/.agents/skills`, and
`all` maps the local Ubuntu or iStoreOS/OpenWrt identity to the corresponding
locked system collection. Consumer, scope, destination and explicit selectors
remain available only as advanced recovery options. No new kai-skills release,
zsetup core or Product Configuration was required.

The four source roots are:

- `https://dl.istoreos.com/binary/kai/kai-skills`
- `https://fw.d4ctech.com/binary/kai/kai-skills`
- `https://fw20.koolcenter.com/binary/kai/kai-skills`
- fallback `https://fw.koolcenter.com/binary/kai/kai-skills`

The origin directory is
`/mnt/sata3-1/istore-data/public_html/binary/kai/kai-skills`.

## Milestone acceptance

| Milestone | Accepted result |
| --- | --- |
| M0 | Distribution, dependency, source-order, selector, integrity and rollback contract frozen. |
| M1 | Schema-3 release manifest validates one immutable artifact per skill/system and exact SHA-256, size, root, expanded size and file count. |
| M2 | Deterministic builder emits 32 individual skills plus the Ubuntu and iStoreOS locked system collections. |
| M3 | zsetup implements bounded safe atomic `archive extract`, `checksum` and `checksum-tree`; traversal, links, devices, duplicates, limits and cancellation are covered. |
| M4 | One release-bound Business Installer downloads only through the Product Config source group and verifies every byte before activation. |
| M5 | Managed state supports install, idempotent reinstall, upgrade, shared ownership and uninstall while preserving user-modified/unowned paths. |
| M6 | Codex, Claude and OpenCode user/project destinations are covered; explicit custom targets remain available. |
| M7 | One generic entrypoint, 32 fixed skill entrypoints and two fixed system entrypoints are generated and deterministic. |
| M8 | Product Config preserves FastNet, Linkspace, ks-cli and kspeeder, adds only the dedicated kai source group and Ubuntu/OpenWrt kai selectors. |
| M9 | Immutable kai-skills artifacts were staged at the owned origin and read back through all four HTTPS sources before pointer activation. |
| M10 | zsetup and kai pointers were activated with rollback snapshots; Ubuntu public matrices and real iStoreOS/OpenWrt install/upgrade/uninstall passed. |
| M11 | One stable `/setup.sh` URL bootstraps zsetup and accepts either `--skill` or `--system`; Product Config remains the only current-release pointer. |
| M12 | The stable channel accepts `SKILL_ID` or `all`, defaults to `~/.agents/skills`, auto-detects Ubuntu/iStoreOS and preserves the complete argument interface for recovery. |

## Frozen public identities

- kai-skills release: `1.2.4`
- release manifest SHA-256: `f112f021d7fb6516b6b38853ecad6a53cece334105ce2a4b88158469121d2fdf`
- Business Installer SHA-256: `eaec9e95ae4eba5c546db9e6ad8806b0cae0fad0a93eb592e125126aadb77a09`
- channel `setup.sh`/`install.sh` SHA-256: `ff8227aeab02ed62ef7b448d9c5e6626c1e0640518d700330ab4aef3da5a1bd4`
- publication manifest SHA-256: `e45a9fdf114090396221ac2370a9f96c53406f306aa23bbe1b2e169c34c6a59c`
- publication checksum-list SHA-256: `4b60dea39e5348cecf36c693574cf5a6c9f19d870472969296edc97c809dacb3`
- zsetup release: `0.6.4`
- Linux x86_64 SHA-256: `9e87c8bf447cc14eb1a8d2ebfc5cfc2377bed4fcb99539c9175b644f5f10a237`
- Product Config SHA-256: `247318a4cc472823afd467a6507f913590b23d27cf3009b00cce7a4eb0b70121`
- Product Config identity: `kai-skills-1.2.4-core-0.6.4-d43e8a6b5310`

The retained rollback snapshots are:

- zsetup: `/mnt/sata3-1/istore-data/public_html/binary/zsetup/.windows-rollback-20261109T045219Z-2817161`
- kai-skills pointers: `/mnt/sata3-1/istore-data/public_html/binary/kai/.kai-skills-rollback-1.2.3-20261109T0453Z`
- pre-channel pointers: `/mnt/sata3-1/istore-data/public_html/binary/kai/.kai-skills-channel-rollback-20261109T-channel-v2`
- pre-`setup.sh` channel: `/mnt/sata3-1/istore-data/public_html/binary/kai/.kai-skills-channel-rollback-20261109T-before-setup`
- pre-simplified channel: `/mnt/sata3-1/istore-data/public_html/binary/kai/.kai-skills-channel-rollback-20261109T-simplified-v1`

Immutable historical releases, including kai-skills `1.2.3` and zsetup
`0.6.0`–`0.6.3`, were retained.

## Final verification

- Rust `cargo test --all-targets` passed for 0.6.4.
- Native Linux foreground, background, storage, configuration, fault, version,
  network and 1000-round stress gates passed.
- aarch64, armv7 and mipsel QEMU network/local-metadata gates passed with their
  declared non-native scope.
- Real OpenWrt 24.10.4 x86_64/musl detected `os=openwrt`, selected the iStoreOS
  public collection, and installed, upgraded and removed all 23 locked skills.
- The OpenWrt jq build without Oniguruma completed the same lifecycle. This
  finding caused the 1.2.4 compatibility release; regex-dependent package/state
  validation was replaced with equivalent portable jq character validation.
- The public root entrypoint passed Codex, Claude and OpenCode × user/project
  install, upgrade and uninstall on Ubuntu. The Ubuntu system collection
  installed and removed all 10 locked skills.
- The public `setup.sh` was executed through the documented curl pipe with a
  new HOME and no zsetup on PATH. It bootstrapped zsetup 0.6.4, installed the
  single `kai-software` skill, all 10 locked Ubuntu skills and all 23 locked
  iStoreOS skills. The same script and command shape handled all selections.
- The M12 candidate was executed with a new HOME and no zsetup on PATH using
  only positional `kai-software`; the skill was installed at
  `~/.agents/skills`. Positional `all --dry-run --json` auto-detected Ubuntu,
  retained consumer `codex` and scope `user`, and selected the exact 10-member
  locked collection. Fixture-backed channel tests also covered OpenWrt/iStoreOS,
  unknown-system recovery, help without bootstrap and legacy full arguments.
- By `2026-11-09T07:15:18Z`, all four public sources returned the exact new
  `setup.sh`, identical `install.sh`, publication manifest and publication
  checksum-list bytes. The canonical curl pipe was then executed with only
  `kai-software`, and with `all --dry-run --json`, against an isolated HOME and
  no zsetup on PATH; both passed through the public URL.
- All four sources returned identical `setup.sh` and compatibility `install.sh`
  bytes, publication schema 2, checksum list and stable 1.2.4. The new path
  initially returned 404, matching the previously recorded publication delay;
  it converged without changing bytes at 2026-11-09T06:09:49Z.
- Four-source immutable readback covered 20 representative 1.2.4 files. Final
  core/kai pointer readback covered 24 files and verified exact sizes and
  SHA-256 values using zsetup. The origin's complete publication and core
  `SHA256SUMS` sets passed.
- Production has no release lock or test canary directory left behind.

The initial final OpenWrt run correctly failed before installation because its
jq lacked optional regex support. One product optimization produced 1.2.4 and
0.6.4; the corrected candidate passed on the same device. A separate first
prepublication retry corrected only the test fixture (the atomic archive output
must not be pre-created) and did not change product code.
