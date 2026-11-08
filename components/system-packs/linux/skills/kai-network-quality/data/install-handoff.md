# Software installation network handoff

The owning software workflow retains authority over installation, credentials,
package policy, and retries. FastNet receives only a bounded observation request.

## Required input

- `schemaVersion: 1`.
- Profile `software-install`.
- Stable, non-secret target IDs and explicit HTTP(S) endpoints from the install
  plan or structured native failure.
- A shared opaque `metadata.operationId` for plan, install attempt, diagnosis,
  remediation, verification, and the optional single retry.
- A timeout in `budget.timeoutSeconds` and response-byte limit in
  `budget.maxResponseBytes`.

Copy [the complete JSON example](diagnose-request.example.json), replacing only
the target ID, explicitly authorized URL, operation ID and agreed budgets. This
schema is owned by FastNet 0.8.0's `netdiag.Request`, `Budget` and `Metadata`
types (`netdiag/types.go`); both `agent validate` and `agent execute` read it.
For example, a 10-second, 4096-byte request has these exact fields:

```json
{
  "schemaVersion": 1,
  "profile": "software-install",
  "targets": [{"id": "metadata", "url": "https://example.invalid/metadata.json"}],
  "budget": {"timeoutSeconds": 10, "maxResponseBytes": 4096},
  "metadata": {"operationId": "replace-with-owning-operation-id"}
}
```

The example URL is a placeholder, not an authorized endpoint. A top-level
`operationId`, `targets[].operationId` or `budget.maxTransferBytes` is invalid.
Keep `metadata.operationId` when correcting a request: never remove correlation
to work around a schema failure. Create the request as a private mode-0600 file,
validate without network traffic, then execute the skill wrapper with
`KAIPLUS_CONFIRMED=1` only under the existing endpoint/budget authorization.
Require `command="fastnet agent execute"` and matching `result.operationId` in
the result. Report findings even when the network condition is unhealthy; a
missing/mismatched operation ID is an incomplete handoff, not a successful one.

URL userinfo is forbidden. Query strings may be necessary for the local request,
but must never be repeated in model context, logs, reports, or evidence. Prefer
an equivalent unsigned metadata endpoint when it answers the same question.

## Escalate to FastNet

- DNS resolution failure or timeout.
- TCP connect failure or timeout.
- TLS negotiation, certificate-chain, hostname, or clock-related failure.
- Transport reset or repeated incomplete transfer.
- Advertised IPv6 with IPv6 path failure and working IPv4 comparison.
- HTTP 429 or 5xx suggesting endpoint/path availability.
- Measured target transfer below the relevant network baseline.

## Do not classify as network quality

- HTTP 401, 403, or 404 without separate transport evidence.
- Missing dependency, unsupported architecture, package conflict, or postinstall
  failure.
- Signature, hash, trust-policy, or package-manager acceptance failure.
- Invalid package name/version or unavailable catalog entry.

## Outcome routing

- Base WAN and multiple unrelated targets degraded: target system-network owner.
- Base WAN healthy but one target path degraded: `kai-download-acceleration`.
- Endpoint policy status: owning software/provider workflow.
- TLS trust/clock finding: target system diagnostics.
- No comparable improvement after remediation: do not retry installation.
- Comparable improvement: the software owner may perform one retry with the
  original package identity and policy.
