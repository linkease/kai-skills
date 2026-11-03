# Isolated dependency acceptance and troubleshooting

## Execution prerequisites

Use the iStoreOS/OpenWrt integration only on that target. Ubuntu uses its own System Pack and runtime/service lifecycle. Package installation is not dependency installation. Discover the target's opkg/is-opkg or apk integration; install the feed's integrated mise package, verify storage/runtime_dir, then enter mise-exec. Select and verify a complete runtime version with mise-runtime before any recipe here. For a remote Agent, stage the complete program/helpers using its Target Transport and run in the same mise-exec environment. Keep addresses/credentials outside these files.

Runtime selection (`mise use` or explicit `mise exec`) and Python venv activation are separate. Another SSH/tool call loses shell activation; the dependency helper re-enters mise-exec and reactivates an explicitly supplied VIRTUAL_ENV. Never use system Python/global dependencies to satisfy this test.

Check service health and per-tool capabilities with `ks-cli status --json` and `ks-cli doctor pip|npm|go --json`. OpenWrt uses UCI/procd and system packages/iStore; do not follow an ordinary Linux service installer hint there. Explain plans show actual adapter ports, not completed requests. DNS must resolve the relevant dl-* hosts to loopback, and the installed gateway must provide valid TLS. Use its actual configured admin/TLS ports; 5443/5003 are not universal.

## Repeatable recipes

`smoke.sh TOOL RESOLVED_VERSION NEW_ABSOLUTE_DIRECTORY` enters integration and leaves all test assets, caches, plan.json and client.log under that new directory. Supply authorization with KAIPLUS_CONFIRMED=1, including possible start of the already installed service. It rejects an existing directory. Repeat with a fresh directory; do not clear another application's caches or alter global configuration. Storage checks must precede large downloads.

The helper first writes runtime.json from the selected SDK's probe. result.json records schemaVersion, operation, status, exitCode, environment_validation, runtime_validation, client_validation and gateway_validation. A successful client-only run exits 0 but reports status=partial and gateway_validation=pending. A runtime or client failure records failed/not-run phases and preserves its exit code. Pending evidence is not a failed download and is not confirmed acceleration.

For a readable, already captured current-instance gateway log, use `smoke.sh TOOL RESOLVED_VERSION NEW_ABSOLUTE_DIRECTORY CURRENT_GATEWAY_LOG ACTUAL_TLS_PORT`. This optional mode requires sha256sum. It snapshots the log prefix before downloads, checks it was not replaced/truncated, and examines only newly appended lines in gateway.log. All runtime/client gates and matching metadata/artifact evidence are required for status=passed, gateway_validation=confirmed. Insufficient evidence or client direct fallback exits nonzero even if the dependency ran successfully. Obtain gateway logs using the installed instance's supported logging method; do not assume logread captures stdout or silently change persistent service configuration. Missing log access keeps the three-argument run partial until a separate current-window evidence check completes.

`evidence.sh --json TOOL CLIENT_LOG CURRENT_WINDOW_GATEWAY_LOG ACTUAL_TLS_PORT` emits a separate scoped gateway-evidence receipt; the existing text mode remains supported. Confirmation requires exitCode=0 and gateway_validation=confirmed, never just the word passed from an SDK or client receipt. Logs and receipts remain target-local; do not put machine paths/addresses in skills. Capture a fresh window after restart/log rotation.

### Python/pip

The recipe uses explicit `mise exec python@VERSION -- python -m venv`, activates .venv, validates interpreter prefix and pip path, then runs:

```sh
ks-cli pip install --no-cache-dir --disable-pip-version-check --only-binary=:all: -vv idna==3.10
python -c 'import idna; assert idna.__version__ == "3.10"; print(idna.encode("例子.测试"))'
ks-cli pip check
```

Client settings are scoped to this smoke: PIP_CONFIG_FILE=/dev/null, no inherited extra indexes/trusted-host, no user-site packages. TLS and index-provided hashes remain intact. Pure-Python idna avoids an accidental native-extension build.

Require a successful /simple/idna/ request to `dl-pypi`, any requested metadata, and the idna 3.10 wheel to `dl-pypi-files`, all on the observed port. `python -m pip` can work while the global pip script fails for missing realpath: test the actual venv launcher via ks-cli pip. If it still needs realpath, inspect launcher ownership and discover an appropriate provider in feeds; don't patch installed files or guess package names.

### Node/npm

The recipe creates a project requiring is-number 7.0.0, runs ks-cli npm install with a new cache, then ks-cli npm ci with a second new cache. Both use HTTP logs, prefer-online, no audit/fund and ignore-scripts (this pure JS demo needs no lifecycle script). Run Node through the explicit installed version:

```js
const isNumber = require("is-number")
if (!isNumber(42) || isNumber("abc")) process.exit(1)
const lock = require("./package-lock.json")
if (!lock.packages["node_modules/is-number"].integrity) process.exit(1)
```

Require actual metadata /is-number and artifact /is-number/-/is-number-7.0.0.tgz requests to dl-npm, plus matching gateway completions and lock integrity. npm can normalize standard-registry tarballs to its configured registry, but a lockfile/custom CDN/Git dependency can remain direct. Inspect actual logs; do not promise blanket coverage. Keep Node installation and npm dependency validation as separate results; an existing Node SDK cannot establish a successful new installation.

### Go modules

The recipe creates a real module with `require github.com/google/uuid v1.6.0` and a program importing it and parsing/printing a fixed UUID. It uses independent GOMODCACHE/GOCACHE/GOPATH, GOTOOLCHAIN=local and process-scoped GOENV=off (so persisted private-module bypasses cannot contaminate this public demo), then:

```sh
ks-cli go mod download -x github.com/google/uuid@v1.6.0
ks-cli go mod verify
ks-cli go run .
```

Download the explicit module so Go writes its package checksum to go.sum even with a pruned module graph; verify alone does not populate that entry. Require module .mod/.info and .zip requests under `/github.com/google/uuid/@v/`, go.sum verification and the actual program output. Keep GOSUMDB enabled; private-module skip patterns and GOINSECURE need separate review. This demo clears private-module bypass patterns only in its process. For a fresh initialized project with this importing program, `ks-cli go get -x github.com/google/uuid@v1.6.0` is also supported: require the resulting go.mod requirement/go.sum, then run the same verify and program checks. Go SDK tarball download is a different route. GOTOOLCHAIN=local prevents a dependency test silently downloading another SDK.

## Gateway evidence and acceptance

Start/end a bounded log capture for the actual installed instance during a fresh test. Read its actual procd/service log configuration; don't assume stdout lands in logread. Keep other test traffic out of the captured window. Capture client logs, installed port/explain plan, loopback DNS/TLS evidence, exact package/version and runtime validation results. Never supply old session logs as current-run evidence.

Run `evidence.sh TOOL CLIENT_LOG GATEWAY_LOG ACTUAL_TLS_PORT` for these pinned smoke recipes. It correlates exact metadata/artifact paths, the actual client port, successful gateway done/positive bytes (including direct_race completion without a separate GET), and successful PyPI index records. It refuses cache-only, unrelated artifacts, wrong-port, incomplete and observed client-direct traffic. It proves the matched route evidence only: also require the recipe's successful install/check/run result and current-instance/DNS provenance before final acceptance.

New gateway versions emit `download gateway pypi-index host=... path=/simple/idna/ http_status=200 status=ok bytes=...`. Wheel/metadata artifacts use pypi-files completion logs, with optional GET events. Older versions without that index event require independently matching current-instance access logs/manual inspection; the checker deliberately returns insufficient evidence, not a fabricated pass. A plugin upgrade is a separate authorized package operation, not automatically required to diagnose.

Distinguish:

- `result=gateway-confirmed`: this recipe's index/module metadata and artifact requests match the supplied current-run logs.
- `result=client-direct-observed`: actual client request/VCS lines show direct sources; inspect whether fallback succeeded and report the mixed route. Go uses GOPROXY=<gateway>,direct; 404/410 may lead to VCS fallback. Don't turn off sumdb to hide it.
- `result=insufficient-evidence`: no matching fresh request/completion, missing index observability, failed transfer, wrong port or cache-only result. Successful import alone cannot fill the gap.

Gateway `selected=origin`, `npmjs`, `google`, pythonhosted or another direct candidate still means gateway processing. `strategy=direct_fallback` inside a gateway log is a gateway strategy, not proof the client bypassed it. Capability/readiness results and route-state snapshots describe support/state; they are not download proof. Node has no dedicated route-state requirement.

## Failure decisions

| Evidence | Next step |
| --- | --- |
| Missing ks-cli/mise or integrated entrypoint | Discover and install the supported system package; no generic curl installer |
| Failed doctor / missing capabilities | Read actual service/port/version; use packages/iStore for required component updates |
| Connection refused / remote-only route 403 | Check service, configured port and loopback DNS; remote Agent commands must run on the target |
| TLS/checksum/signature/sumdb failure | Check clock, certificate, expected integrity and source logs; preserve checks |
| pip 127 realpath / inactive venv | Inspect actual launcher, activate project's venv in the same shell and retry ks-cli pip |
| pip wheel metadata 404 while canonical source returns 200 | Correlate cached mirror failure with same-request completion; older gateways could commit the mirror error before a successful retry. Preserve client status/body and gateway build identity, then use an authorized fixed gateway build; do not skip metadata/TLS/hashes or label a manual retry as a fix |
| npm tarball/Git source outside registry | Inspect lockfile and actual request; use a supported separate lane or report direct coverage |
| Go successful only after direct fallback | Report direct success separately; diagnose proxy status/routing without relabeling it as gateway success |

Historical Python/idna and Go/uuid user results are described in the contract document. They are not this change's tests. Mocked contract tests and real device downloads must be reported separately.
