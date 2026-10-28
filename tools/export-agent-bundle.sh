#!/bin/sh
set -eu

platform=""
mode=""
consumer=""
output=""

usage() {
  echo "usage: export-agent-bundle.sh --platform istoreos --mode on-device --consumer opencode --output DIR" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --platform) shift; [ "$#" -gt 0 ] || usage; platform="$1" ;;
    --mode) shift; [ "$#" -gt 0 ] || usage; mode="$1" ;;
    --consumer) shift; [ "$#" -gt 0 ] || usage; consumer="$1" ;;
    --output) shift; [ "$#" -gt 0 ] || usage; output="$1" ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
  shift
done

[ "$platform" = "istoreos" ] || { echo "failed: only platform=istoreos is supported" >&2; exit 2; }
[ "$mode" = "on-device" ] || { echo "failed: only mode=on-device is supported" >&2; exit 2; }
[ "$consumer" = "opencode" ] || { echo "failed: only consumer=opencode is supported" >&2; exit 2; }
[ -n "$output" ] || usage
case "$output" in /|'') echo "failed: unsafe output path" >&2; exit 2 ;; esac

for command in git jq sha256sum; do
  command -v "$command" >/dev/null 2>&1 || { echo "failed: $command is required" >&2; exit 2; }
done

root="${LINKEASE_SKILLS_ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)}"
preset_id="$platform-$mode"
preset_path="$(jq -er --arg platform "$platform" --arg mode "$mode" \
  '.presets[] | select(.platform == $platform and .mode == $mode) | .path' "$root/catalog.json")"
preset="$root/$preset_path"
pack="$root/components/system-packs/$platform"

[ -d "$preset/skills" ] || { echo "failed: generated preset skills are missing" >&2; exit 1; }
[ -d "$pack/agents" ] || { echo "failed: canonical Agent instructions are missing" >&2; exit 1; }
[ -f "$pack/home-prompts.json" ] || { echo "failed: canonical home prompts are missing" >&2; exit 1; }
[ ! -e "$output" ] || { echo "failed: output already exists: $output" >&2; exit 1; }

sh "$root/tools/verify-generated.sh" >/dev/null

parent="$(dirname "$output")"
mkdir -p "$parent"
parent="$(CDPATH= cd -- "$parent" && pwd -P)"
output="$parent/$(basename "$output")"
stage="$(mktemp -d "$parent/.linkease-agent-bundle.XXXXXX")"
trap 'rm -rf "$stage"' EXIT HUP INT TERM

mkdir -p "$stage/agents" "$stage/skills"
cp -R "$pack/agents"/. "$stage/agents"/
cp -R "$preset/skills"/. "$stage/skills"/
cp "$pack/home-prompts.json" "$stage/home-prompts.json"

names="$stage/.skill-names"
: >"$names"
for skill in "$stage"/skills/*; do
  [ -d "$skill" ] || continue
  if [ ! -f "$skill/SKILL.md" ]; then
    jq -e --arg folder "$(basename "$skill")" '(.resources // []) | index($folder) != null' "$preset/preset.json" >/dev/null || {
      echo "failed: undeclared resource in $skill" >&2; exit 1;
    }
    continue
  fi
  folder="$(basename "$skill")"
  name="$(sed -n '/^---[[:space:]]*$/,/^---[[:space:]]*$/s/^name:[[:space:]]*//p' "$skill/SKILL.md" \
    | head -n 1 | sed 's/[[:space:]]*$//')"
  [ -n "$name" ] || { echo "failed: skill has no frontmatter name: $folder" >&2; exit 1; }
  [ "$name" = "$folder" ] || { echo "failed: skill folder/name mismatch: $folder != $name" >&2; exit 1; }
  printf '%s\n' "$name" >>"$names"
done

[ -s "$names" ] || { echo "failed: bundle contains no skills" >&2; exit 1; }
duplicate="$(LC_ALL=C sort "$names" | uniq -d | head -n 1)"
[ -z "$duplicate" ] || { echo "failed: duplicate skill name: $duplicate" >&2; exit 1; }
rm -f "$names"

tree_digest="$(
  find "$stage" -type f | sed "s#^$stage/##" | LC_ALL=C sort |
  while IFS= read -r relative_file; do
    printf '%s  %s\n' "$(sha256sum "$stage/$relative_file" | awk '{print $1}')" "$relative_file"
  done | sha256sum | awk '{print "sha256:" $1}'
)"

skills="$(find "$stage/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f \
  | sed 's#/SKILL.md$##' | xargs -n 1 basename | LC_ALL=C sort | jq -Rsc 'split("\n") | map(select(length > 0))')"
jq -n \
  --arg platform "$platform" \
  --arg mode "$mode" \
  --arg consumer "$consumer" \
  --arg presetId "$preset_id" \
  --arg sourceCommit "$(git -C "$root" rev-parse HEAD)" \
  --arg sourceState "$(if [ -z "$(git -C "$root" status --porcelain --untracked-files=all)" ]; then echo committed; else echo worktree; fi)" \
  --arg sourceDigest "$(jq -r '.sourceDigest' "$preset/preset.json")" \
  --arg treeDigest "$tree_digest" \
  --argjson componentVersions "$(jq '.componentVersions' "$preset/preset.json")" \
  --argjson skills "$skills" \
  --argjson resources "$(jq ' .resources // []' "$preset/preset.json")" \
  --argjson skillAliases "$(jq '.skillAliases // {}' "$preset/preset.json")" \
  '{schemaVersion:1,platform:$platform,mode:$mode,consumer:$consumer,presetId:$presetId,
    sourceCommit:$sourceCommit,sourceState:$sourceState,sourceDigest:$sourceDigest,treeDigest:$treeDigest,
    componentVersions:$componentVersions,skills:$skills,resources:$resources,skillAliases:$skillAliases}' >"$stage/manifest.json"

mv "$stage" "$output"
trap - EXIT HUP INT TERM
echo "ok: exported preset=$preset_id consumer=$consumer output=$output"
