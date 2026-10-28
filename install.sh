#!/bin/sh
set -eu

action="install"
platform=""
usage_mode=""
consumer=""
target_skills=""
target_config=""
legacy_profile=""
describe_id=""
output_json="0"
install_mode="copy"
force="0"
dry_run="0"

usage() {
  cat >&2 <<'EOF'
Usage:
  sh install.sh --list [--json]
  sh install.sh --describe PRESET_ID
  sh install.sh --platform PLATFORM --mode on-device|remote-control \
    --consumer codex|opencode|generic [--target-skills DIR] [--dry-run] [--force]
  sh install.sh --platform PLATFORM --mode MODE --consumer CONSUMER --upgrade
  sh install.sh --platform PLATFORM --mode MODE --consumer CONSUMER --uninstall

Compatibility:
  sh install.sh --profile istoreos|remote-control-istoreos --target-skills DIR
  sh install.sh --profile NAME --target-config DIR
EOF
}

need_value() {
  [ "$#" -gt 0 ] || { usage; exit 2; }
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --list) action="list" ;;
    --json) output_json="1" ;;
    --describe) shift; need_value "$@"; action="describe"; describe_id="$1" ;;
    --platform) shift; need_value "$@"; platform="$1" ;;
    --mode) shift; need_value "$@"; usage_mode="$1" ;;
    --consumer) shift; need_value "$@"; consumer="$1" ;;
    --target-skills|--target) shift; need_value "$@"; target_skills="$1" ;;
    --target-config) shift; need_value "$@"; target_config="$1" ;;
    --profile) shift; need_value "$@"; legacy_profile="$1" ;;
    --dry-run) dry_run="1" ;;
    --upgrade) action="upgrade" ;;
    --uninstall) action="uninstall" ;;
    --copy) install_mode="copy" ;;
    --symlink) install_mode="symlink" ;;
    --force) force="1" ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
  shift
done

root="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
catalog="$root/catalog.json"
command -v jq >/dev/null 2>&1 || { echo "failed: jq is required" >&2; exit 2; }

if [ "$action" = "list" ]; then
  if [ "$output_json" = "1" ]; then
    jq '.presets' "$catalog"
  else
    jq -r '.presets[] | "\(.platform)\t\(.mode)\t\(.id)\t\(.title)"' "$catalog"
  fi
  exit 0
fi

if [ "$action" = "describe" ]; then
  [ -n "$describe_id" ] || { usage; exit 2; }
  jq -e --arg id "$describe_id" '.presets[] | select(.id == $id)' "$catalog" || {
    echo "failed: unknown preset $describe_id" >&2
    exit 1
  }
  exit 0
fi

legacy_src=""
if [ -n "$legacy_profile" ]; then
  echo "notice: --profile is deprecated; prefer --platform and --mode" >&2
  case "$legacy_profile" in
    istoreos) platform="istoreos"; usage_mode="on-device" ;;
    remote-control-istoreos) platform="istoreos"; usage_mode="remote-control" ;;
    *) legacy_src="$root/$legacy_profile" ;;
  esac
fi

if [ -n "$legacy_src" ]; then
  [ -d "$legacy_src" ] || { echo "failed: unknown legacy profile $legacy_profile" >&2; exit 1; }
  [ -n "$target_skills" ] || [ -n "$target_config" ] || {
    echo "Where should this legacy profile be installed?" >&2
    exit 2
  }
  preset_id="$legacy_profile"
  preset_dir="$legacy_src"
  skills_root="$legacy_src/skills"
else
  [ -n "$platform" ] || {
    echo "Which device platform do you want to manage?" >&2
    exit 2
  }
  [ -n "$usage_mode" ] || {
    echo "Will the Agent run on the device, or control it remotely?" >&2
    exit 2
  }
  case "$usage_mode" in on-device|remote-control) ;; *) echo "failed: mode must be on-device or remote-control" >&2; exit 2 ;; esac

  match_count="$(jq --arg platform "$platform" --arg mode "$usage_mode" \
    '[.presets[] | select(.platform == $platform and .mode == $mode)] | length' "$catalog")"
  [ "$match_count" -eq 1 ] || {
    echo "failed: no unique preset for platform=$platform mode=$usage_mode" >&2
    exit 1
  }
  preset_id="$(jq -r --arg platform "$platform" --arg mode "$usage_mode" \
    '.presets[] | select(.platform == $platform and .mode == $mode) | .id' "$catalog")"
  preset_path="$(jq -r --arg id "$preset_id" '.presets[] | select(.id == $id) | .path' "$catalog")"
  skills_path="$(jq -r --arg id "$preset_id" '.presets[] | select(.id == $id) | .skillsRoot' "$catalog")"
  preset_dir="$root/$preset_path"
  skills_root="$preset_dir/$skills_path"
fi
[ -d "$skills_root" ] || { echo "failed: preset skills are missing at $skills_root" >&2; exit 1; }

resolve_codex_target() {
  if [ -n "${CODEX_HOME:-}" ]; then
    printf '%s\n' "$CODEX_HOME/skills"
  elif [ -d /config/.codex ]; then
    printf '%s\n' /config/.codex/skills
  else
    printf '%s\n' "$HOME/.codex/skills"
  fi
}

if [ -z "$target_skills" ] && [ -z "$target_config" ]; then
  case "${consumer:-generic}" in
    codex) target_skills="$(resolve_codex_target)" ;;
    opencode) target_skills="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills" ;;
    generic) echo "Where should the selected skills be installed? Use --target-skills DIR." >&2; exit 2 ;;
    *) echo "failed: consumer must be codex, opencode, or generic" >&2; exit 2 ;;
  esac
fi

case "${consumer:-generic}" in codex|opencode|generic) ;; *) echo "failed: consumer must be codex, opencode, or generic" >&2; exit 2 ;; esac

destination="${target_skills:-$target_config/skills}"
if [ "$dry_run" = "1" ] && [ "$action" != "uninstall" ]; then
  if [ "$force" = "1" ]; then replacement="replace"; else replacement="preserve"; fi
  printf '%s\n' \
    "preset=$preset_id" \
    "source=$preset_dir" \
    "destination=$destination" \
    "consumer=${consumer:-generic}" \
    "install_mode=$install_mode" \
    "replacement=$replacement"
  for skill in "$skills_root"/*; do
    [ -f "$skill/SKILL.md" ] && printf 'skill=%s\n' "$(basename "$skill")"
  done
  exit 0
fi

if [ -z "$legacy_src" ] && [ -z "$target_config" ]; then
  set -- --target "$destination"
  case "$install_mode" in copy) set -- "$@" --copy ;; symlink) set -- "$@" --symlink ;; esac
  [ "$force" = "0" ] || set -- "$@" --force
  [ "$dry_run" = "0" ] || set -- "$@" --dry-run
  case "$action" in
    upgrade) set -- "$@" --upgrade ;;
    uninstall) set -- "$@" --uninstall ;;
  esac
  exec sh "$preset_dir/install.sh" "$@"
fi

case "$action" in
  upgrade|uninstall)
    echo "failed: lifecycle operations are supported for generated presets installed into a skills directory" >&2
    exit 2
    ;;
esac

copy_or_link_dir() {
  from="$1"
  to="$2"
  [ -d "$from" ] || return 0
  mkdir -p "$(dirname "$to")"
  if [ -e "$to" ] || [ -L "$to" ]; then
    [ "$force" = "1" ] || { echo "failed: $to exists; use --force to replace" >&2; exit 1; }
    rm -rf "$to"
  fi
  case "$install_mode" in
    copy) cp -R "$from" "$to" ;;
    symlink) ln -s "$from" "$to" ;;
  esac
}

copy_file() {
  from="$1"
  to="$2"
  [ -f "$from" ] || return 0
  mkdir -p "$(dirname "$to")"
  if [ -e "$to" ] || [ -L "$to" ]; then
    [ "$force" = "1" ] || { echo "failed: $to exists; use --force to replace" >&2; exit 1; }
    rm -f "$to"
  fi
  cp "$from" "$to"
}

mkdir -p "$destination"
for skill in "$skills_root"/*; do
  if [ ! -f "$skill/SKILL.md" ]; then
    [ -f "$preset_dir/preset.json" ] && jq -e --arg name "$(basename "$skill")" '(.resources // []) | index($name) != null' "$preset_dir/preset.json" >/dev/null || continue
  fi
  copy_or_link_dir "$skill" "$destination/$(basename "$skill")"
done

if [ -n "$target_config" ]; then
  case "$preset_id" in
    istoreos-on-device) config_source="$root/components/system-packs/istoreos" ;;
    istoreos-remote-control) config_source="$root/remote-control-istoreos" ;;
    *) config_source="$preset_dir" ;;
  esac
  copy_or_link_dir "$config_source/agents" "$target_config/agents"
  copy_file "$config_source/home-prompts.json" "$target_config/home-prompts.json"
  copy_file "$config_source/manifest.json" "$target_config/kaiplus-profile.json"
fi

echo "ok: installed preset=$preset_id destination=$destination"
