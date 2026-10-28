#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/linkease-skills-m2.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
  echo "failed: $*" >&2
  exit 1
}

canonical_count=0
for skill in "$root"/istoreos/skills/*; do
  [ -f "$skill/SKILL.md" ] || continue
  canonical_count=$((canonical_count + 1))
  grep -q '^owner: system-pack/istoreos$' "$skill/SKILL.md" ||
    fail "missing canonical owner in $skill/SKILL.md"
  grep -q '^systems: istoreos$' "$skill/SKILL.md" ||
    fail "missing systems metadata in $skill/SKILL.md"
done
[ "$canonical_count" -eq 20 ] || fail "expected 20 canonical iStoreOS skills, got $canonical_count"

remote_count=0
for skill in "$root"/remote-control-istoreos/*; do
  [ -f "$skill/SKILL.md" ] || continue
  remote_count=$((remote_count + 1))
  case "$(basename "$skill")" in
    istoreos-ssh-ops|quickstart-router-api) ;;
    *) fail "system skill duplicated in remote preset: $skill" ;;
  esac
done
[ "$remote_count" -eq 0 ] || fail "remote preset must not own skills, got $remote_count"

sh "$root/remote-control-istoreos/install.sh" --target "$tmp/direct" --copy >/dev/null
direct_count="$(find "$tmp/direct" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l | tr -d ' ')"
[ "$direct_count" -eq 24 ] || fail "direct preset install expected 24 skills, got $direct_count"

sh "$root/install.sh" --profile remote-control-istoreos \
  --target-skills "$tmp/root" --copy >/dev/null
root_count="$(find "$tmp/root" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l | tr -d ' ')"
[ "$root_count" -eq 24 ] || fail "root installer expected 24 skills, got $root_count"

for installed in "$tmp/direct"/istoreos-*; do
  [ -f "$installed/SKILL.md" ] || continue
  name="$(basename "$installed")"
  cmp "$root/istoreos/skills/$name/SKILL.md" "$installed/SKILL.md" >/dev/null ||
    fail "installed skill is not canonical: $name"
done

for installed in "$tmp/direct"/kai-*; do
  name="$(basename "$installed")"
  cmp "$root/components/system-packs/common/skills/$name/SKILL.md" "$installed/SKILL.md"
done

sh "$root/istoreos/drills/profile-smoke.sh"
sh "$root/remote-control-istoreos/drills/profile-smoke.sh"
sh "$root/tests/architecture/test-catalog.sh"

echo "M2 canonical iStoreOS composition: PASS"
