---
name: luci-http-controller
description: Send bounded authenticated HTTP requests to a bound LuCI target without embedding device-specific endpoints, credentials, or operating-system repair policy.
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.
# LuCI HTTP Controller

The caller explicitly supplies the endpoint, method, body and expected response for an already bound target. This skill handles LuCI login, in-memory cookies, timeout, TLS policy, response bounds, and the generic write gate; it does not decide what an endpoint means.

Keep the password in an environment variable named by `--password-env`. For example:

```sh
go run scripts/lucihttp.go \
  --host router.example --user root --password-env TARGET_LUCI_PASSWORD \
  --prefix /cgi-bin/luci/example GET /status
```

Every non-GET/HEAD method requires `--approve-write` or `TARGET_HTTP_WRITE_APPROVED=YES` under an existing scoped host authorization; flags do not grant host permission. Use `--insecure` only after the user accepts the exact target certificate risk. Responses larger than 8 MiB and timeouts longer than five minutes are rejected.
