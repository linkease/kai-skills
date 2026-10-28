#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/linkease-skills-m10-release.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
  echo "failed: $*" >&2
  exit 1
}

hash_tree() {
  tree="$1"
  find "$tree" -type f | sed "s#^$tree/##" | LC_ALL=C sort |
  while IFS= read -r relative_file; do
    printf '%s  %s\n' "$(sha256sum "$tree/$relative_file" | awk '{print $1}')" "$relative_file"
  done | sha256sum | awk '{print "sha256:" $1}'
}

sh "$root/tools/build-release.sh" "$tmp/release-a" >/dev/null
sh "$root/tools/build-release.sh" "$tmp/release-b" >/dev/null
diff -ru "$tmp/release-a" "$tmp/release-b" >/dev/null || fail "release build is not deterministic"
manifest="$tmp/release-a/release-manifest.json"
jq -e '.schemaVersion == 1 and (.sourceCommit | test("^[a-f0-9]{40}$")) and (.artifacts | length == 20)' "$manifest" >/dev/null
[ "$(jq -r '.artifacts[].presetId' "$manifest" | sort -u | wc -l | tr -d ' ')" -eq 10 ] || fail "release does not contain ten presets"

jq -r '.artifacts[] | [.presetId,.format,.path,.sha256,.treeDigest] | @tsv' "$manifest" |
while IFS="$(printf '\t')" read -r preset_id format archive expected_sha expected_tree; do
  actual_sha="sha256:$(sha256sum "$tmp/release-a/$archive" | awk '{print $1}')"
  [ "$actual_sha" = "$expected_sha" ] || fail "$archive checksum mismatch"
  extract="$tmp/extract-$preset_id-${format%%.*}"
  mkdir -p "$extract"
  case "$format" in
    tar.gz) tar -xzf "$tmp/release-a/$archive" -C "$extract" ;;
    zip) unzip -q "$tmp/release-a/$archive" -d "$extract" ;;
    *) fail "unknown archive format $format" ;;
  esac
  bundle="$(find "$extract" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [ -n "$bundle" ] || fail "$archive has no bundle root"
  jq -e --arg id "$preset_id" --arg tree "$expected_tree" '.presetId == $id and .treeDigest == $tree' "$bundle/SOURCE.json" >/dev/null
  [ "$(hash_tree "$bundle/skills")" = "$expected_tree" ] || fail "$archive skill tree mismatch"
  sh "$bundle/install.sh" --target "$tmp/installed-$preset_id-${format%%.*}" >/dev/null
done

# Checkout root and platform-subdirectory entry points remain intuitive.
sh "$root/install.sh" --platform windows --mode remote-control --consumer generic --target-skills "$tmp/from-root" >/dev/null
[ -f "$tmp/from-root/target-ssh-powershell-controller/SKILL.md" ] || fail "root installer selected wrong Windows preset"
sh "$root/platforms/macos/remote-control/install.sh" --target "$tmp/from-platform" >/dev/null
[ -f "$tmp/from-platform/target-ssh-controller/SKILL.md" ] || fail "platform installer lacks SSH controller"

echo "M10 deterministic release and three installation entry points: PASS"
