#!/bin/sh
set -eu

root="${LINKEASE_SKILLS_ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)}"
output="${1:-$root/release}"
case "$output" in ''|/) echo "failed: unsafe release output" >&2; exit 2 ;; esac
for command in jq sha256sum tar zip git; do
  command -v "$command" >/dev/null 2>&1 || { echo "failed: $command is required" >&2; exit 2; }
done

sh "$root/tools/verify-generated.sh" >/dev/null
source_commit="${SOURCE_COMMIT:-$(git -C "$root" rev-parse HEAD)}"
case "$source_commit" in *[!0-9a-f]*|'') echo "failed: invalid source commit" >&2; exit 1 ;; esac

source_state=committed
[ -z "$(git -C "$root" status --porcelain --untracked-files=all)" ] || source_state=worktree

tmp="$(mktemp -d "${TMPDIR:-/tmp}/linkease-release.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
artifacts="$tmp/artifacts"
records="$tmp/artifacts.tsv"
mkdir -p "$artifacts" "$output"
: >"$records"

jq -r '.presets[].id' "$root/catalog.json" |
while IFS= read -r preset_id; do
  preset_path="$(jq -r --arg id "$preset_id" '.presets[] | select(.id == $id) | .path' "$root/catalog.json")"
  preset="$root/$preset_path"
  platform="$(jq -r '.platform' "$preset/preset.json")"
  mode="$(jq -r '.mode' "$preset/preset.json")"
  version="$(jq -r --arg platform "$platform" '.componentVersions[$platform]' "$preset/preset.json")"
  tree_digest="$(jq -r '.treeDigest' "$preset/preset.json")"
  source_digest="$(jq -r '.sourceDigest' "$preset/preset.json")"
  bundle="linkease-skills-$preset_id-v$version"
  stage="$tmp/stage-$preset_id/$bundle"
  mkdir -p "$stage"
  cp -R "$preset"/. "$stage"/
  jq -n \
    --arg presetId "$preset_id" --arg version "$version" --arg sourceCommit "$source_commit" \
    --arg treeDigest "$tree_digest" --arg sourceDigest "$source_digest" --arg sourceState "$source_state" \
    '{schemaVersion:1,presetId:$presetId,version:$version,sourceCommit:$sourceCommit,sourceState:$sourceState,treeDigest:$treeDigest,sourceDigest:$sourceDigest}' \
    >"$stage/SOURCE.json"
  find "$tmp/stage-$preset_id" -exec touch -t 198001010000 {} +

  tar_name="$bundle.tar.gz"
  zip_name="$bundle.zip"
  tar --sort=name --mtime='1980-01-01 UTC' --owner=0 --group=0 --numeric-owner \
    -C "$tmp/stage-$preset_id" -czf "$artifacts/$tar_name" "$bundle"
  (CDPATH= cd -- "$tmp/stage-$preset_id" && find "$bundle" -type f | LC_ALL=C sort | zip -X -q "$artifacts/$zip_name" -@)
  for format_name in "tar.gz:$tar_name" "zip:$zip_name"; do
    format="${format_name%%:*}"
    name="${format_name#*:}"
    digest="sha256:$(sha256sum "$artifacts/$name" | awk '{print $1}')"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$preset_id" "$platform" "$mode" "$version" "$format" "$name" "$digest" "$tree_digest" >>"$records"
  done
done

artifacts_json="$(jq -Rn '[inputs | split("\t") | {presetId:.[0],platform:.[1],mode:.[2],version:.[3],format:.[4],path:.[5],sha256:.[6],treeDigest:.[7]}]' <"$records")"
jq -n --arg sourceCommit "$source_commit" --arg sourceState "$source_state" --argjson artifacts "$artifacts_json" \
  '{schemaVersion:1,sourceCommit:$sourceCommit,sourceState:$sourceState,artifacts:$artifacts}' >"$artifacts/release-manifest.json"
cp "$artifacts"/* "$output"/
echo "ok: built $(jq '.artifacts | length' "$output/release-manifest.json") release artifacts in $output"
