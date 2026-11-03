#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/linkease-generated-check.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

sh "$root/tools/generate-platforms.sh" "$tmp/platforms" >/dev/null
diff -ru "$root/platforms" "$tmp/platforms" >/dev/null || {
  diff -ru "$root/platforms" "$tmp/platforms" >&2 || true
  echo "failed: generated platforms are stale; run tools/generate-platforms.sh" >&2
  exit 1
}
echo "ok: generated platforms match canonical components"
if [ -f "$root/business-catalog.json" ]; then sh "$root/tools/verify-business.sh"; fi
