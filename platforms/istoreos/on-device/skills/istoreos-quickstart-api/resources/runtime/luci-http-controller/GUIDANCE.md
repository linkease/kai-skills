---
name: luci-http-controller
description: Send bounded authenticated HTTP requests to a bound LuCI target without embedding device-specific endpoints, credentials, or operating-system repair policy.
owner: transport/luci-http
systems: any
requires: http-client
---

# LuCI HTTP Controller

Use this transport only when a selected system skill names the endpoint, method, body, expected response, and safety class. This skill handles LuCI login, in-memory cookies, timeout, TLS policy, response bounds, and the generic write gate; it does not decide what an endpoint means.

Keep the password in an environment variable named by `--password-env`. For example:

```sh
go run scripts/lucihttp.go \
  --host router.example --user root --password-env TARGET_LUCI_PASSWORD \
  --prefix /cgi-bin/luci/example GET /status
```

Every non-GET/HEAD method requires `--approve-write` or `TARGET_HTTP_WRITE_APPROVED=YES` after the system skill's own approval policy has passed. Use `--insecure` only after the user accepts the exact target certificate risk. Responses larger than 8 MiB and timeouts longer than five minutes are rejected.
