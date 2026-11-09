# Kai Skills zsetup distribution contract

Status: Accepted for implementation. The machine-readable authority is
[`kai-skills-zsetup-contract.json`](kai-skills-zsetup-contract.json).

## Product boundary

One Product Configuration application, `kai-skills`, dispatches every public
single skill and the locked iStoreOS and Ubuntu system collections. A system
selection defaults to the existing `on-device` collection; `--mode` can select
another published, locked mode. Product Configuration selects and verifies the
Business Installer. The Business Installer owns skill selection, lifecycle,
conflict handling, upgrade and removal.

The first supported targets are Linux and OpenWrt. The public consumers are
Codex, Claude and OpenCode at explicit user or project scope. Native Windows and
macOS entrypoints remain a later compatibility release and cannot be inferred
from Linux acceptance.

The public system id `istoreos` deliberately maps to the zsetup runtime selector
`os=openwrt`, because iStoreOS exposes the OpenWrt operating-system identity to
the native context detector. This mapping changes only Product Configuration
selection; users continue to request `--system istoreos`.

The destination matrix is part of the public contract. User scope resolves to
`~/.agents/skills`, `~/.claude/skills`, and
`${XDG_CONFIG_HOME:-~/.config}/opencode/skills`. Project scope resolves below
`KAI_SKILLS_PROJECT_ROOT` (or the current directory) as `.agents/skills`,
`.claude/skills`, and `.opencode/skills`. An explicit `--target-skills` wins over
these defaults while the selected consumer and scope remain in ownership state.

## Public source roots

The three primary roots are, in order:

```text
https://dl.istoreos.com/binary/kai/kai-skills
https://fw.d4ctech.com/binary/kai/kai-skills
https://fw20.koolcenter.com/binary/kai/kai-skills
```

The final fallback is:

```text
https://fw.koolcenter.com/binary/kai/kai-skills
```

Its origin directory is:

```text
/mnt/sata3-1/istore-data/public_html/binary/kai/kai-skills
```

Release directories are immutable. Upload and HTTPS readback of every selected
file on all four sites, followed by single-skill and system canaries, precede
Product Configuration activation. Rollback restores the previous configuration
and mutable entrypoints; it does not delete immutable releases.

## Entry and selection

The public current-channel entry is stable and contains no Kai release version:

```sh
curl -fsSL https://fw.koolcenter.com/binary/kai/kai-skills/setup.sh | \
  sh -s -- --skill kai-software --consumer codex --scope user
```

The same entry installs a complete locked system collection:

```sh
curl -fsSL https://fw.koolcenter.com/binary/kai/kai-skills/setup.sh | \
  sh -s -- --system istoreos --consumer codex --scope user
```

`ubuntu` is the other supported system id. The mutable channel entry bootstraps
the current stable zsetup when necessary and delegates selection to Product
Configuration. `install.sh` is a compatibility alias with identical bytes;
the documented canonical URL is `setup.sh`, which was introduced after the
old release-bound `install.sh` cache. The launcher never embeds or exports a
Kai release identity. Product
Configuration selects the exact immutable Business Installer, which in turn
pins the exact release manifest and selected package.

For a machine that already has zsetup, the equivalent direct entry is:

```sh
zsetup install kai-skills --foreground -- \
  --skill kai-software --consumer codex --scope user
```

A system collection uses:

```sh
zsetup install kai-skills --foreground -- \
  --system istoreos --consumer codex --scope user
```

Versioned generated scripts remain available for diagnostics and exact rollback,
but are not user-facing copy commands. They may fix the selection and expected
release. The root channel entry is the only normal public one-click URL.

## Trust and dependency boundary

The trust chain is Product Configuration to the exact Business Installer, the
installer to the exact release manifest, the manifest to the exact selected
package, and zsetup verification before safe extraction. A neighboring remote
`SHA256SUMS` file is not a trust root.

zsetup owns HTTPS download, size and SHA-256 verification, bounded staging and
safe archive extraction. The minimum product version is therefore 0.6.0; this
version must expose the archive operation as a stable business interface rather
than requiring an external `tar`, `gzip` or hash command. POSIX shell, full jq
and ordinary base file operations remain allowed for the managed lifecycle.

The first-bootstrap phase needs POSIX shell plus one HTTPS client (`curl` for the
documented command, or `wget` for its equivalent). If `sha256sum` or OpenSSL is
already present it verifies the initial zsetup bytes; otherwise HTTPS is the
initial trust boundary. No downloaded program can verify itself before first
execution. The bootstrap does not modify shell profiles or overwrite another
system zsetup.

After zsetup is ready, target installation must not execute or contact Git,
GitHub, gh, Node.js, npm/npx, ks-cli, kspeeder, curl or wget. Release
construction may use developer tools, but their presence never becomes a
device installation dependency.

## Completion gate

Installation, idempotent repetition, dry-run, coherent upgrade, conflict
preservation and ownership-aware uninstall must pass for single skills and both
system collections. The complete iStoreOS/Ubuntu by Codex/Claude/OpenCode matrix
must pass from newly downloaded bytes. Corruption, truncation, unsafe archive
paths, source failure, cancellation and insufficient storage must leave the
previous installation unchanged.
