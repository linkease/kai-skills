---
name: kai-download-acceleration
description: 检查文件、Git、Docker 和开发下载加速，并核对本次网关与校验证据。
owner: system-pack/common
systems: ubuntu, debian, istoreos, openwrt, linux, macos, windows
triggers: 文件下载慢, GitHub 文件, 下载链接, docker pull, Docker 镜像下载, git clone, 下载加速
negative-triggers: 网速慢, 测速, 宽带速度, pip install, npm ci, go mod, uv sync
auto-use: prefer
routing-group: system-primary
needs-fresh-data: true
cost: medium
---

Routed Git reads require native Git >=2.37. The client resolves only its local
TLS gateway hostname within the child Git process; Host/SNI, normal certificate
verification and the repository's original GitHub URL remain intact. Do not
change the target's DNS or hosts file to make the local route work.

Before calling Bash scripts, prepare an existing compatible Bash with kai-tool-bootstrap. On Windows the first Bash bootstrap uses native PowerShell. Follow the selected target Transport; the controller OS does not choose the target package manager.

Use the selected target and Transport. Prepare missing Bash/jq/ks-cli with
kai-tool-bootstrap; service setup belongs to that target's platform lifecycle.
Doctor and Explain are read-only. Reuse the user's authorization for the stated
target and operation.

For a public file with an independently obtained SHA256, run
`bash scripts/accelerate.sh download HTTPS_URL DESTINATION SHA256`. Its parent
directory must exist. The helper stages the file, checks SHA256 and activates it
exclusively; conflicting files and symlinks are preserved. An already matching
file is reused. Native failures keep their original exit status and stderr.
File downloads explicitly disable service startup and default to ks-cli's auto
mode. Let its speed policy choose direct access or a gateway; keep its original
route receipt. `KAI_DOWNLOAD_MODE=auto|direct|accelerated|race` explicitly selects
a mode when needed. A verified direct download is successful content without an
acceleration claim; a gateway selection still needs matching transfer evidence.

`doctor TOOL` and `explain TOOL -- NATIVE_ARGUMENTS...` forward the native
read-only JSON contracts. Docker/file use service Doctor; Docker Explain is its
own native plan. They do not execute the requested download. Service Doctor is
informational for an auto file download: an unavailable gateway may still allow
the client's direct fallback.

For a public GitHub repository, use
`git-clone HTTPS_REPOSITORY DESTINATION FULL_COMMIT`. A new owned directory is
checked out at the verified commit; a matching clean managed clone is reused.
Foreign or changed repositories are preserved. The helper uses process-local
ks-cli Git routing and never writes global Git insteadOf or credentials.
This operation requires native Git with HTTPS support on the target. Prepare it
through that target's native package provider when absent; a missing Git is a
failed prerequisite, not a successful download. On iStoreOS review the package
plan first and preserve the firmware's curl, libraries and TLS configuration.

For an immutable Docker image, use `docker-pull IMAGE@sha256:DIGEST` with an
existing authorized daemon. Digest references pass through the native client,
so its daemon must already list the gateway mirror (by default
`https://registry.linkease.net:5443`; override with
`KAI_DOCKER_GATEWAY_MIRROR`). The helper checks that prerequisite and the pulled
RepoDigest. It reports the daemon identity and data root without changing its
configuration. A matching digest proves content; gateway logs must separately
confirm the manifest and blob requests.

Preparing the mise executable belongs to kai-tool-bootstrap. On Windows its
verified installer reuses an existing ks-cli in auto mode; distinguish this
download from mise's later SDK downloads. SDK selection and installation belong to kai-dev-environment, and npm/pip/uv/Go
project work belongs to kai-project-dependencies. Their explicit acceleration
mode delegates the actual native commands through ks-cli. Keep TLS, signatures,
hashes, existing lock formats and Go sumdb enabled. Public registry routing does
not imply coverage of private credentials, Git dependencies or every mise backend.

Content/function success alone leaves acceleration pending. Confirm it with
matching client and gateway evidence from the same service instance and request
window, including the actual metadata/index and artifact requests. Distinguish
client direct fallback, gateway-origin requests and gateway-cache hits.
Use `scripts/evidence.sh MANIFEST CLIENT_LOG GATEWAY_LOG` for a bounded structured
check. Read [the proof contract](data/evidence.md) before constructing a
manifest; populate client outcomes and freshness from the actual execution and
Transport, rather than from the expected result. This requires the service's
`download-observation.v1` log format. Missing evidence leaves acceleration pending.

When `kai-network-quality` supplies a FastNet finding, keep its scope intact.
Broad WAN degradation across unrelated targets is not proof that a target
gateway will help. A healthy base path with one degraded metadata/artifact path
may enter this skill's Doctor/Explain workflow. HTTP 401/403/404 and package
policy failures remain with their owner; do not label them acceleration
problems. Preserve the shared `operationId`, then let FastNet repeat the same
bounded diagnosis after any route remediation. Improved FastNet evidence proves
only the network observation changed; this skill must still prove the selected
route with its own current-instance client and gateway evidence.

For native iStoreOS evidence only, resolve `istoreos-docker-acceleration-istoreenhance`
or `istoreos-kspeeder-domainfold-fetch` through the target System Pack when the
ordinary client plan cannot explain its native integration. Load one helper on demand.
