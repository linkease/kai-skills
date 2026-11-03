#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/linkease-skills-m4.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
  echo "failed: $*" >&2
  exit 1
}

[ -L "$root/istoreos" ] || fail "legacy istoreos path must be a compatibility symlink"
[ "$(readlink "$root/istoreos")" = "components/system-packs/istoreos" ] ||
  fail "legacy istoreos symlink points to the wrong canonical pack"

jq -e '.id == "common" and .layer == "common"' \
  "$root/components/system-packs/common/pack.json" >/dev/null
jq -e '.id == "linux" and .extends == ["common"]' \
  "$root/components/system-packs/linux/pack.json" >/dev/null
jq -e '.id == "openwrt" and .extends == ["linux"] and .match.osFamily == "openwrt"' \
  "$root/components/system-packs/openwrt/pack.json" >/dev/null
jq -e '.id == "istoreos" and .version == "2.0.0" and .extends == ["openwrt"] and .match.distribution == "istoreos"' \
  "$root/components/system-packs/istoreos/pack.json" >/dev/null

sh "$root/tools/generate-platforms.sh" "$tmp/first" >/dev/null
sh "$root/tools/generate-platforms.sh" "$tmp/second" >/dev/null
diff -ru "$tmp/first" "$tmp/second" >/dev/null || fail "generator is not deterministic"
sh "$root/tools/verify-generated.sh"

for mode in on-device remote-control; do
  preset="$root/platforms/istoreos/$mode"
  cmp "$preset/preset.json" "$preset/.generated.json" >/dev/null ||
    fail "$mode generated marker differs from preset metadata"
  jq -e --arg mode "$mode" \
    '.schemaVersion == 1 and .generated == true and .mode == $mode and
     (.sourceDigest | test("^sha256:[a-f0-9]{64}$")) and
     (.treeDigest | test("^sha256:[a-f0-9]{64}$")) and
     (.componentVersions | length > 0)' "$preset/preset.json" >/dev/null ||
    fail "invalid generated metadata for $mode"
  sh "$preset/install.sh" --target "$tmp/install-$mode" --copy >/dev/null
done

on_device_count="$(find "$tmp/install-on-device" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l | tr -d ' ')"
remote_count="$(find "$tmp/install-remote-control" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l | tr -d ' ')"
[ "$on_device_count" -eq 22 ] || fail "on-device preset expected 22 skills, got $on_device_count"
[ "$remote_count" -eq 24 ] || fail "remote-control preset expected 24 skills, got $remote_count"
[ ! -e "$tmp/install-on-device/target-ssh-controller" ] || fail "on-device preset contains SSH transport"
[ -e "$tmp/install-remote-control/target-ssh-controller" ] || fail "remote-control preset lacks SSH transport"

diff -ru "$root/skills/kai-software" \
  "$root/platforms/istoreos/on-device/skills/kai-software" >/dev/null ||
  fail "generated system skill differs from independent package"

mkdir -p "$tmp/stale-repo"
cp -R "$root/components" "$root/tools" "$root/platforms" "$root/catalog.json" "$tmp/stale-repo/"
printf '\nM4 drift sentinel\n' >> \
  "$tmp/stale-repo/components/system-packs/common/skills/kai-software/SKILL.md"
if sh "$tmp/stale-repo/tools/verify-generated.sh" >/dev/null 2>&1; then
  fail "canonical source change did not trigger generated drift failure"
fi

sh "$root/tests/architecture/test-catalog.sh"
echo "M4 generated platform presets: PASS"
