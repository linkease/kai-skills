# LinkEase Skills repository guidance

## When a user gives you this repository

1. Read `business-catalog.json` for independent skills and business collections; `catalog.json` remains the versioned compatibility index for system presets.
2. Select the business skill or business collection the user requested. A universal skill can be downloaded before a target is connected; identify the actual target before execution.
3. If the user requests every applicable skill for one system, select `--platform PLATFORM --all --mode MODE`. Never expand a single business request into a complete system collection.
4. Preview with `sh install.sh --skill ID`, `--bundle ID`, or `--platform PLATFORM --all --mode MODE`, plus `--consumer CONSUMER --dry-run`. Show destination, members, versions, conflicts and any legacy migration before changing the Agent's skills directory.
5. Reuse authorization already given for the destination and replacement policy. Shared version conflicts require a coherent explicit upgrade; user edits and unowned directories are preserved.

Never install every platform by default. Never install from `components/`. Only system-wide or remote execution selection needs platform/mode information at installation time; do not block downloading an independent skill on those questions. Do not ask users to choose a System Pack or Transport.

On a native Windows target without Bash, use the selected distribution's root
`install.ps1 -Action Plan` with `-Skill ID`, `-Bundle ID`, or
`-Platform windows -All -Mode MODE`, plus the consumer/destination. It locates
the native Bash bootstrap in selected members or distribution support resources.
For a directly copied independent skill, use its own
`scripts/bootstrap-bash.ps1` or
`resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1` when present.
Native bootstrap supports `-Action Plan` and, within existing authorization,
`-Action Ensure`; root installation uses `-Action EnsureBash` for that explicit
preparation. Verify Git Bash and prepare full jq before shell installation.
For a remote target, use its existing Transport; do not bootstrap tools on the
controller by mistake. WSL is a separate Linux target.

For Codex use `--consumer codex`; for OpenCode use `--consumer opencode`; for other Agents use `--consumer generic --target-skills DIR`.

## Repository boundaries

- `components/system-packs`: canonical target operating-system behavior.
- `components/transports`: canonical target connection/execution behavior; no operating-system maintenance policy.
- `components/business.json`: business collections, program requirements and explicit embedded resource dependencies.
- `skills/<id>` and `bundles/*.json`: generated independent packages and exact collection locks. Do not edit them manually.
- `platforms/<device>/<mode>`: generated, self-contained third-party installation presets. Do not edit them manually.
- Kai consumes canonical System Packs and its own Target Transport, not third-party remote-control presets.

Credentials, target addresses, fingerprints, and device-specific state must remain outside this repository and model context. Unknown or changed SSH host keys are a hard stop.

Shared skills in `common` and `linux` use only `kai-` identifiers and publish no
historical skill aliases. Internal platform adapter resources are classified by
`compatibilityResources`, independently of public skill names. Keep genuine
platform-specific skills under their platform prefix.
