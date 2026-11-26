# Current-instance download evidence

The verifier takes a JSON manifest, the original bounded client log, and the
matching bounded gateway log (at most 64 MiB each). It reads only these files.
The native gateway emits `download observation {JSON}` with schemaVersion 1,
an instance nonce, request ID, UTC start/end times, actual listener port, TLS,
method/host/path, status, bytes and SHA256. Query strings are omitted. Handler
completion alone does not establish a valid artifact or a successful client.

The Transport must bind the current service instance to the capture: for example,
the isolated lab records its owned container, binary SHA, reported source commit,
fresh data directory and log capture. On a resident service inspect its actual
listener/process and bounded current logs. Do not borrow a nonce or a successful
log from an older instance.

The manifest has:

- schemaVersion: 1; channel: file, git, docker, sdk-python, sdk-node, sdk-go,
  npm, pip, uv or go-modules; instanceId; actual numeric tlsPort.
- window.startUnix and endUnix from the target's clock around the actual commands.
- client.exitCode, contentValidation and functionalValidation from the original
  native result and actual verification. Only file may use not-required for
  functionalValidation. client.logSha256 hashes the supplied original client log.
- client.directObserved: an explicit boolean derived from execution diagnostics;
  unknown routing is insufficient to assert a confirmed path.
- requests: expected role (metadata/artifact), method, actual host and escaped
  path. Every artifact has its independently obtained SHA256. For Git, a verified
  expected.commit matching client.commit supplies its content identity instead.

File needs an artifact request. Other channels need both metadata/index and
artifact requests. Freeze these from supported native operations and their
source descriptions. Listing a planned URL without an actual successful matching
request does not pass. In particular, this does not imply every mise version API,
private registry, Git dependency or Docker client policy is accelerated.

A channel describes its declared metadata/artifact flow. Report auxiliary
discovery and telemetry separately. For example, the CPython precompiled channel
covers its mise catalog and release archive; a PyPy catalog lookup or mise
telemetry request does not establish or replace either required request.
`client.directObserved` refers to direct access for the required channel
resources. Direct access for either required role prevents confirmation.

The lab's independent loopback HTTP origin tests native direct classification
without depending on public WAN availability. This is an isolated negative
fixture; the public file helper continues to require HTTPS. Untrusted TLS is
tested separately through an actual HTTPS request with default verification.

For cold acceptance, set requireCold=true only with actual client.cacheCold and
gatewayFresh evidence. gatewayFresh refers to the expected resources, not merely
an unrelated empty cache. Earlier matching requests in the same instance reject
this claim. Do not delete users' caches to obtain it. A new lab instance/project
is the default acceptance approach. Upstream CDN cache and the gateway's own
cache are separate facts.

The result keeps content/function conclusions separate from acceleration. Wrong
instance, window, listener, response digest, missing metadata/artifact, observed
client direct fallback or unconfirmed cold state return 4. A confirmed path is
not a throughput measurement. Report a gateway's canonical origin selection,
mirror selection, and cache observations from their original diagnostics.
