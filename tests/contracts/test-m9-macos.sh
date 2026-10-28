#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)"
pack="$root/components/system-packs/macos"
controller="$root/components/transports/ssh/skills/target-ssh-controller"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/linkease-skills-m9.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
  echo "failed: $*" >&2
  exit 1
}

jq -e '.id == "macos" and .match.osFamily == "macos" and .requires == ["target-shell:posix"]' \
  "$pack/pack.json" >/dev/null
jq -e '.kernelName == "Darwin" and .productVersion != "" and .initSystem == "launchd"' \
  "$root/tests/fixtures/macos/facts.json" >/dev/null

for skill in "$pack"/skills/*/SKILL.md; do
  grep -q '^owner: system-pack/macos$' "$skill"
  grep -q '^systems: macos$' "$skill"
  grep -q '^requires: target-shell:posix$' "$skill"
done
for script in "$pack"/skills/*/scripts/*.sh; do
  sh -n "$script"
done
if grep -R -E 'systemctl|journalctl|/etc/os-release|openwrt|opkg|apt-get' "$pack"/skills --include='*.sh' >/dev/null; then
  fail "macOS scripts contain Linux or OpenWrt-specific commands"
fi
grep -q '8192' "$pack/skills/macos-system-diagnostics/scripts/inspect.sh"
grep -q 'TARGET_CHANGE_APPROVED' "$pack/skills/macos-launchd-logs/scripts/apply.sh"
if TARGET_CHANGE_APPROVED= sh "$pack/skills/macos-launchd-logs/scripts/apply.sh" system com.example.worker kickstart >/dev/null 2>&1; then
  fail "launchd apply succeeded without approval"
fi

cat >"$tmp/fake-keygen" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$tmp/fake-ssh" <<'EOF'
#!/bin/sh
cat >"$FAKE_REMOTE_CAPTURE"
EOF
chmod +x "$tmp/fake-keygen" "$tmp/fake-ssh"
: >"$tmp/known_hosts"
: >"$tmp/host-sentinel"
printf 'rm -f "%s"\n' "$tmp/host-sentinel" |
  TARGET_ID=macos-fixture TARGET_SSH_HOST=mac.example TARGET_SSH_USER=operator \
  TARGET_SSH_KNOWN_HOSTS="$tmp/known_hosts" TARGET_SSH_BIN="$tmp/fake-ssh" \
  TARGET_SSH_KEYGEN_BIN="$tmp/fake-keygen" FAKE_REMOTE_CAPTURE="$tmp/remote.sh" \
  sh "$controller/scripts/target-ssh.sh" inspect >/dev/null
[ -f "$tmp/host-sentinel" ] || fail "macOS target script executed on controller host"
grep -q 'rm -f' "$tmp/remote.sh" || fail "macOS script was not sent to SSH adapter"

sh "$root/tools/generate-platforms.sh" "$tmp/platforms" >/dev/null
for mode in on-device remote-control; do
  sh "$tmp/platforms/macos/$mode/install.sh" --target "$tmp/install-$mode" >/dev/null
done
on_device="$(find "$tmp/install-on-device" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l | tr -d ' ')"
remote="$(find "$tmp/install-remote-control" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l | tr -d ' ')"
[ "$on_device" -eq 8 ] || fail "macOS on-device expected 8 skills, got $on_device"
[ "$remote" -eq 9 ] || fail "macOS remote-control expected 9 skills, got $remote"
[ -f "$tmp/install-remote-control/target-ssh-controller/SKILL.md" ] || fail "macOS SSH controller missing"

sh "$root/tools/verify-generated.sh"
sh "$root/tests/architecture/test-catalog.sh"
echo "M9 macOS vertical slice: PASS"
