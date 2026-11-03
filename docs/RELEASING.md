# Business skill release and lifecycle contract

The public unit is one independent skill. Business and system collections lock
those same bytes; they do not introduce another discoverable skill. Target
program installation and service operations remain separate from installing skills.

## Build a development candidate

On the build host, Python 3, jq and Git are required. Target installers require
Bash, full jq, SHA256 tools and ordinary shell utilities, without Python.

```sh
sh tools/generate-business.sh
sh tools/generate-platforms.sh
sh tools/verify-generated.sh
sh tools/build-release.sh /path/to/new-candidate-a
sh tools/build-release.sh /path/to/new-candidate-b
diff -ru /path/to/new-candidate-a /path/to/new-candidate-b
python3 tools/release/business_release.py verify /path/to/new-candidate-a
```

Use new output directories. Builds refuse to overwrite an existing candidate.
The default matrix is 31 independent skills, two business collections and ten
system collections, each in ZIP and tar.gz: 86 archives. A single skill archive
has exactly one root named after the skill and preserves all package bytes.
Its provenance is in its existing `resources/source-metadata.json` and the
external release manifest; extra release files are not injected into the skill.

Collections include only their exact members, a filtered catalog, their lock,
the shell and native PowerShell entry points, a support bootstrap and SOURCE.json.
They contain no source checkout, native test configuration or credentials.
`release-manifest.json` schema 2 records the actual Git commit, sourceState,
build/installer input hashes, canonical resource sources and hashes, package
digests, exact collection membership, artifact hashes and frozen requirements.
`SHA256SUMS` covers that manifest and every archive.

Archive order, modes, ownership and timestamps are normalized. Comparing two
builds requires the same inputs and build toolchain. Building from a dirty tree
is allowed for development, records `sourceState=worktree`, and cannot pass the
formal release gate. `SOURCE_COMMIT` cannot replace the actual Git identity.
The manifest's `validationStatus=unverified` means building alone proves no
native acceptance. A passing gate emits a separate result bound to that exact
manifest; it never edits the frozen candidate.

Legacy preset artifacts remain available with
`sh tools/build-release.sh --legacy NEW_OUTPUT`: 20 schema-1 preset archives.
They are a separate compatibility release, not the new business release index.

## Install and use

See [README](../README.md) for all five supported workflows: single skill,
business collection, system all, remote execution and managed upgrade/removal.

- Single archive: unpack and copy its one skill directory into the Agent's skills
  directory. This is self-contained, manual ownership. For managed single-skill
  installation, use the repository root installer with `--skill ID`.
- Business archive: after unpacking, run
  `sh install.sh --bundle development --consumer generic --target-skills DIR --dry-run`.
  `software-management` is the other business selection.
- System archive: use, for example,
  `sh install.sh --platform windows --all --mode on-device --consumer generic --target-skills DIR --dry-run`.
  A remote collection uses `--mode remote-control`; task programs belong on the
  selected target and use its existing authorized transport.

On Windows before Bash exists, run `./install.ps1 -Action Plan -Bundle development
-TargetSkills DIR` through native PowerShell. The receipt locates the selected
member's embedded bootstrap. Use its Plan, then the explicitly authorized
`-Action EnsureBash` preparation when needed. A system selection instead uses
`-Platform windows -All -Mode on-device`. With an existing trusted Git Bash,
pass `-TrustedBash 'C:/Program Files/Git/bin/bash.exe'` and Plan continues to the
shell dry-run. Windows managed installation supports copy and rejects symlink
before any writes. This native entry does not install jq; prepare full jq with
the bootstrap tool workflow before managed shell installation.

Review the dry-run, then remove `--dry-run`; native PowerShell uses `-Action Install`.
Keep the same selection and destination for `--upgrade` and `--uninstall` through
Bash. Shared members survive removal of another selection. Coordinated shared
updates use `--upgrade --update-shared`. User modifications, foreign directories
and changed links stop the transaction and remain intact. Do not erase ownership
records to bypass a conflict. Retain a symlink distribution at its original
location on supported Unix systems; copying archives is the portable default.

## Require evidence before publishing

Commit the completed sources and regenerated outputs. Build and freeze a clean
candidate before collecting final native evidence:

```sh
python3 tools/release/business_release.py evidence-template CANDIDATE > evidence.json
python3 tools/release/business_release.py gate CANDIDATE --evidence evidence.json
```

The template intentionally contains pending results and empty receipts; it is
not test evidence. The gate requires all BM0–BM9 required acceptance criteria
and the 30 frozen native positive scenarios. Each result has `status=passed`,
the exact package digest map specified in the template, and nonempty receipt
references `{path, sha256}`. Receipt paths are relative to evidence.json, cannot
escape its directory or use symlinks, and their hashes are checked. Results bind
to the SHA256 of the entire frozen release manifest. Missing, failed, blocked,
skipped or stale evidence fails. Source changes require a new candidate and
affected native evidence, never a fabricated success or rewritten old receipt.
Human review must confirm that referenced receipts demonstrate each scenario;
the gate checks completeness and identity, not the truth of arbitrary log text.

CI runs development contracts on PR/push. Manual `Business skill distribution`
execution additionally downloads `kai-business-native-evidence` from the supplied
GitHub Actions run ID and enforces this gate. That artifact must contain
evidence.json and its relative receipt files for the exact candidate commit.
An absent artifact or mismatched candidate fails. No workflow publishes files.

## Publish the frozen files and verify a fresh download

BM10 requires a chosen channel, version, target URL and publication authorization.
Record the previous known-good release URL and manifest digest before changing
the recommendation. Upload the same manifest, SHA256SUMS and all 86 archives
from the accepted candidate to one immutable version location. Do not rebuild
during upload or mix commits. The manifest's `kind`, `id`, platforms,
architectures and collection mode provide the three discovery dimensions.

Keep a trusted local copy of the accepted manifest (or verify its digest through
the release channel), then re-download all published files:

```sh
python3 tools/release/business_release.py fetch \
  --manifest CANDIDATE/release-manifest.json \
  --base-url https://RELEASE_HOST/VERSION \
  --output /path/to/new-download
```

The downloader requires HTTPS, fetches new bytes into a staging directory,
requires the remote manifest to match the pinned local manifest exactly,
verifies every archive SHA256, source, member payload, lock and installer,
then promotes the completed download directory. On failure it leaves no completed
output and changes no recommendation. `--allow-http` exists only for local fixture
tests. An archive hash is integrity relative to the trusted manifest, not an
independent publisher signature.

BM10 also requires five-system actual use and lifecycle checks from those newly
downloaded bytes. Retain the previous release until these pass. If they fail,
keep failure evidence, stop promotion, fix sources and freeze a new candidate.
Do not mark the current untested candidate recommended. Development completion,
native acceptance, release-ready and published remain separate recorded states.
