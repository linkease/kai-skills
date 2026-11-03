#!/bin/sh
set -eu
root="${LINKEASE_SKILLS_ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)}"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/business-generated-check.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
sh "$root/tools/generate-business.sh" "$temporary" >/dev/null
diff -ru "$root/skills" "$temporary/skills" >/dev/null || { echo 'failed: independent skill packages are stale' >&2; exit 1; }
diff -ru "$root/bundles" "$temporary/bundles" >/dev/null || { echo 'failed: collection locks are stale' >&2; exit 1; }
cmp "$root/business-catalog.json" "$temporary/business-catalog.json" >/dev/null || { echo 'failed: business catalog is stale' >&2; exit 1; }
echo 'ok: independent packages and collection locks match canonical sources'
