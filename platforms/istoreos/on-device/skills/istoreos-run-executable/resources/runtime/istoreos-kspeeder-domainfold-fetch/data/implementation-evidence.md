# DomainFold implementation evidence

Read this file only when implementation provenance or supported-host behavior
matters to the answer.

## URL mapping

- Default origin routes live in `kspeeder/domainfold/routes.go`.
- `/gh` maps `https://github.com` to a host derived from the route key and
  configured alias suffix, normally `gh.linkease.net`.
- URL remapping is implemented by `kspeeder/domainfold/url_mapper.go`.
- The device interface is `POST /api/domainfold/remap` with
  `{"url":"<origin>"}`, returning `output` and `admin_path`.
- Use `POST /api/domainfold/plan` when support/readiness/strategy must be
  established before a download.

## Local dispatch

`kspeeder/cmd/multi/proxy_handlers.go` dispatches traffic by Host on the TLS
listener. DomainFold admin proxy paths are registered from the configured route
table and forward locally while retaining the desired TLS server name.

## Git Smart HTTP

`kspeeder/domainfold/git_bypass.go` recognizes Git discovery and RPC requests,
including `info/refs?service=git-*`, `git-upload-pack`, and
`git-receive-pack`. These flows retain streaming/request-body semantics, which
is why native Git must operate on a remapped URL instead of treating a
repository as one downloadable file.

Default source history includes GitHub, GitLab, Gitea and Codeberg. It does not
prove Gitee support. The current device route response is authoritative.

## Trust limits

Source paths above are provenance hints tied to the deployed KSpeeder revision.
When repository code and device behavior disagree, report both revisions and
prefer observed device behavior for diagnosis.
