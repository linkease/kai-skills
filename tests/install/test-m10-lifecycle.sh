#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/linkease-skills-m10-install.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
preset="$root/platforms/macos/on-device"
target="$tmp/skills"

fail() {
  echo "failed: $*" >&2
  exit 1
}

mkdir -p "$target/user-skill"
printf '%s\n' 'user-owned sentinel' >"$target/user-skill/SKILL.md"
before="$(find "$target" -type f -exec sha256sum {} \; | LC_ALL=C sort | sha256sum | awk '{print $1}')"
if LINKEASE_INSTALL_TEST_FAIL_BEFORE_SWAP=1 sh "$preset/install.sh" --target "$target" >/dev/null 2>&1; then
  fail "injected install failure succeeded"
fi
after="$(find "$target" -type f -exec sha256sum {} \; | LC_ALL=C sort | sha256sum | awk '{print $1}')"
[ "$before" = "$after" ] || fail "failed transaction changed destination"
[ ! -e "$target/.linkease-skills" ] || fail "failed transaction left ownership state"

sh "$preset/install.sh" --target "$target" >/dev/null
manifest="$target/.linkease-skills/macos-on-device.json"
jq -e '.presetId == "macos-on-device" and (.skills | length == 8)' "$manifest" >/dev/null
[ -f "$target/user-skill/SKILL.md" ] || fail "install removed unrelated user skill"

sh "$preset/install.sh" --target "$target" --upgrade >/dev/null
[ -f "$target/user-skill/SKILL.md" ] || fail "upgrade removed unrelated user skill"

printf '%s\n' 'user modification' >>"$target/macos-system-diagnostics/SKILL.md"
modified="$(sha256sum "$target/macos-system-diagnostics/SKILL.md" | awk '{print $1}')"
if sh "$preset/install.sh" --target "$target" --upgrade >"$tmp/out" 2>"$tmp/upgrade-error"; then
  fail "upgrade replaced a user-modified owned skill"
fi
grep -q 'user-modified skill' "$tmp/upgrade-error"
[ "$(sha256sum "$target/macos-system-diagnostics/SKILL.md" | awk '{print $1}')" = "$modified" ] || fail "failed upgrade changed user content"
if sh "$preset/install.sh" --target "$target" --uninstall >"$tmp/out" 2>"$tmp/uninstall-error"; then
  fail "uninstall removed a user-modified owned skill"
fi
grep -q 'user-modified skill' "$tmp/uninstall-error"
[ -f "$target/macos-system-diagnostics/SKILL.md" ] || fail "failed uninstall removed user content"

rm -rf "$target/macos-system-diagnostics"
cp -R "$preset/skills/macos-system-diagnostics" "$target/macos-system-diagnostics"
sh "$preset/install.sh" --target "$target" --uninstall >/dev/null
[ ! -e "$target/macos-system-diagnostics" ] || fail "clean uninstall retained an owned skill"
[ ! -e "$target/macos-launchd-logs" ] || fail "clean uninstall retained an owned skill"
[ -f "$target/user-skill/SKILL.md" ] || fail "uninstall removed unrelated user skill"
[ ! -e "$manifest" ] || fail "uninstall retained ownership manifest"

echo "M10 atomic install, upgrade, modification protection, and uninstall: PASS"
