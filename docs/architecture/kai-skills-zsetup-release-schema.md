# zsetup release schema 3

Schema 3 is the online zsetup distribution view. It is additive to the existing
schema-2 business release and does not rewrite or reinterpret frozen historical
candidates.

The canonical archive format is deterministic `tar.gz`. zsetup 0.6.0 owns
verified download and safe extraction, so this format does not imply a target
dependency on `tar` or `gzip`. A release contains one artifact for every public
single skill and exactly the locked `istoreos` and `ubuntu` on-device systems.

Within one immutable release directory:

```text
kai-skills-install.sh
release-manifest.json
SHA256SUMS
skills/<skill-id>.tar.gz
systems/istoreos.tar.gz
systems/ubuntu.tar.gz
```

Every artifact record contains `kind`, `id`, the release `version`, relative
`path`, compressed byte `size`, trusted `sha256`, exact `expandedSize` and
`fileCount` extraction limits, extracted `treeDigest`, one safe `root`
directory and the exact ordered `members`. A system record additionally embeds
the exact member lock and its source lock path. Paths are POSIX relative paths;
absolute paths, Windows drive paths, backslashes, empty components and `..` are
invalid.

The generated Business Installer is deliberately outside the manifest digest
graph: Product Configuration pins the installer; the installer pins the exact
manifest bytes; the manifest pins package bytes. `SHA256SUMS` is publication
evidence, not a trust root and not a substitute for any pinned digest.

Source state may be `worktree` during development. Formal release and public
activation require `committed`, complete acceptance evidence and four-site
HTTPS readback.
