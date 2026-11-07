# FastNet installation handoff

The software workflow owns the install plan, package identity, credentials and
retry decision. Do not run a general speed test before every installation. When
the plan exposes HTTP(S) metadata or artifact endpoints, retain bounded,
redacted target identities and one opaque `operationId` outside model context.

Escalate to `kai-network-quality` only after a structured native failure shows
DNS resolution/timeout, TCP connect/timeout, TLS negotiation or certificate
failure, transport reset/incomplete transfer, advertised-but-broken IPv6, HTTP
429/5xx, or target throughput degradation. HTTP 401/403/404, missing
dependencies, unsupported architecture, package conflicts, postinstall errors,
and signature/hash/trust-policy failures remain with the software owner unless
separate transport evidence exists.

Build a `software-install` FastNet request from the owning plan rather than
scraping unbounded logs. Reject URL credentials; never put signed queries or
complete request files in the response. Run FastNet `validate` before the
user-authorized `diagnose`. Route target-only path degradation to
`kai-download-acceleration`; route broad WAN or TLS trust/clock findings to the
target system owner.

After remediation, repeat the same profile, target IDs, budget and operation ID.
Retry the original installation at most once and only when comparable
verification improved. A successful install still requires the native receipt
and meaningful-command verification.
