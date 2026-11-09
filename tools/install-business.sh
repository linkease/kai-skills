#!/bin/sh
# Managed online packages need only the existing shell, jq, and zsetup.  The
# validation filters deliberately avoid jq's optional Oniguruma regex support
# because OpenWrt ships a smaller jq build without it.
set -eu
root="${LINKEASE_BUSINESS_ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)}"
umask 077
skill= bundle= platform= usage_mode= consumer=generic scope=user target= architecture=
all=0 dry=0 action=install install_mode=copy json=0 own_transport=0 update_shared=0
fail() { echo "failed: $*" >&2; exit 2; }
need_value() { [ "$#" -ge 2 ] && [ -n "$2" ] || fail "missing value for $1"; }
safe_id() { case "$1" in ''|*[!a-z0-9-]*) fail "invalid identity $1" ;; esac; }
command -v jq >/dev/null 2>&1 || fail 'prepare jq before managed skill installation'
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) jq() { command jq -b "$@"; } ;; esac
while [ "$#" -gt 0 ]; do
  case "$1" in
    --skill) need_value "$@"; skill="$2"; shift ;;
    --bundle) need_value "$@"; bundle="$2"; shift ;;
    --platform) need_value "$@"; platform="$2"; shift ;;
    --mode) need_value "$@"; usage_mode="$2"; shift ;;
    --architecture) need_value "$@"; architecture="$2"; shift ;;
    --consumer) need_value "$@"; consumer="$2"; shift ;;
    --scope) need_value "$@"; scope="$2"; shift ;;
    --target-skills|--target) need_value "$@"; target="$2"; shift ;;
    --all) all=1 ;;
    --dry-run) dry=1 ;;
    --json) json=1 ;;
    --upgrade) action=upgrade ;;
    --uninstall) action=uninstall ;;
    --copy) install_mode=copy ;;
    --symlink) install_mode=symlink ;;
    --own-transport) own_transport=1 ;;
    --update-shared) update_shared=1 ;;
    --force) fail '--force cannot override package ownership or shared selections' ;;
    --list-skills) action=list-skills ;;
    --list-bundles) action=list-bundles ;;
    --describe-skill) need_value "$@"; action=describe-skill; skill="$2"; shift ;;
    --describe-bundle) need_value "$@"; action=describe-bundle; bundle="$2"; shift ;;
    *) fail "unknown business installation option $1" ;;
  esac
  shift
done
[ "$update_shared" = 0 ] || [ "$action" = upgrade ] || fail '--update-shared requires --upgrade'
if [ "$install_mode" = symlink ]; then
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) fail 'Windows managed installation supports --copy; --symlink is unavailable' ;; esac
fi
catalog="$root/business-catalog.json"
[ -f "$catalog" ] && [ ! -L "$catalog" ] || fail 'business catalog is unavailable; use a complete generated distribution'
jq -e '.schemaVersion==1 and (.skills|type)=="array" and (.defaultPolicy.installAll==false)' "$catalog" >/dev/null || fail 'invalid business catalog'
case "$action" in
  list-skills) jq '.skills' "$catalog"; exit 0 ;;
  list-bundles) jq '.bundles' "$catalog"; exit 0 ;;
  describe-skill) safe_id "$skill"; jq -e --arg id "$skill" '.skills[]|select(.id==$id)' "$catalog"; exit $? ;;
  describe-bundle) safe_id "$bundle"; jq -e --arg id "$bundle" '.bundles[$id] // error("unknown bundle")' "$catalog"; exit $? ;;
esac
count=0; [ -z "$skill" ] || count=$((count+1)); [ -z "$bundle" ] || count=$((count+1)); count=$((count+all))
[ "$count" = 1 ] || fail 'choose exactly one --skill, --bundle or --platform --all'
case "$platform" in ''|ubuntu|debian|istoreos|macos|windows) ;; *) fail 'unsupported target platform' ;; esac
case "$usage_mode" in ''|on-device|remote-control) ;; *) fail 'unsupported execution mode' ;; esac
[ "$all" = 0 ] || { [ -n "$platform" ] && [ -n "$usage_mode" ]; } || fail 'platform --all requires platform and mode'
[ "$usage_mode" != remote-control ] || [ -n "$platform" ] || fail 'remote-control requires target platform'
case "$consumer" in codex|claude|opencode|generic) ;; *) fail 'unsupported consumer' ;; esac
case "$scope" in user|project) ;; *) fail 'unsupported installation scope' ;; esac
if [ -z "$target" ]; then
  if [ "$scope" = project ]; then project_root="${KAI_SKILLS_PROJECT_ROOT:-$(pwd -P)}"; fi
  case "$consumer" in
    codex) if [ "$scope" = project ]; then target="$project_root/.agents/skills"; elif [ -n "${CODEX_HOME:-}" ]; then target="$CODEX_HOME/skills"; else target="$HOME/.agents/skills"; fi ;;
    claude) if [ "$scope" = project ]; then target="$project_root/.claude/skills"; else target="$HOME/.claude/skills"; fi ;;
    opencode) if [ "$scope" = project ]; then target="$project_root/.opencode/skills"; else target="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"; fi ;;
    generic) fail 'specify --target-skills DIR for a generic consumer' ;;
  esac
fi
if command -v cygpath >/dev/null 2>&1; then target="$(cygpath -u "$target")"; fi
case "$target" in ''|/|.|..) fail 'unsafe target directory' ;; esac
case "$target" in /*) ;; *) target="$(pwd -P)/$target" ;; esac
case "$target/" in */../*|*/./*) fail 'use a normalized target path' ;; esac
[ ! -L "$target" ] || fail 'target directory must not be a symlink'
case "$target/" in "$root/"|"$root/skills/"|"$root/components/"*) fail 'cannot install over distribution sources' ;; esac
if [ -n "$skill" ]; then
  safe_id "$skill"; selection="skill:$skill"
  incoming="$(jq -ce --arg id "$skill" '[.skills[]|select(.id==$id)]|if length==1 then . else error("unknown skill") end' "$catalog")" || fail 'unknown skill'
else
  if [ -n "$bundle" ]; then safe_id "$bundle"; lock="$root/bundles/$bundle.json"; selection="bundle:$bundle"
  else lock="$root/bundles/$platform-all-$usage_mode.json"; selection="system:$platform:$usage_mode"; fi
  [ -f "$lock" ] && [ ! -L "$lock" ] || fail 'collection lock is unavailable'
  incoming="$(jq -ce --slurpfile catalog "$catalog" '
    .members | map(. as $locked | [$catalog[0].skills[]|select(.id==$locked.id and .version==$locked.version and .treeDigest==$locked.treeDigest)] |
    if length==1 then .[0] else error("collection member missing or digest mismatch") end)' "$lock")" || fail 'invalid collection lock'
fi
if [ -n "$platform" ]; then
  printf '%s' "$incoming" | jq -e --arg p "$platform" 'all(.[]; (.platforms|index($p))!=null)' >/dev/null || fail 'skill is incompatible with target platform'
fi
if [ -n "$architecture" ]; then
  [ -n "$platform" ] || fail 'architecture requires platform'
  printf '%s' "$incoming" | jq -e --arg p "$platform" --arg a "$architecture" 'all(.[]; (.architectures[$p]|index($a))!=null)' >/dev/null || fail 'unsupported target architecture'
fi
if [ "$usage_mode" = remote-control ] && [ "$own_transport" = 0 ]; then
  transport="$(jq -ce --arg p "$platform" '[.skills[]|select(.kind=="transport" and (.platforms|index($p))!=null)]' "$catalog")"
  incoming="$(printf '%s' "$incoming" | jq -c --argjson transport "$transport" '.+$transport|unique_by(.id)')"
elif [ "$own_transport" = 1 ] && [ "$all" = 1 ]; then
  incoming="$(printf '%s' "$incoming" | jq -c 'map(select(.kind!="transport"))')"
fi
if [ "$all" = 0 ] && { [ -n "$platform" ] || [ -n "$usage_mode" ]; }; then selection="$selection@$platform:$usage_mode"; fi
printf '%s' "$incoming" | jq -e '
  def skill_id:
    type=="string" and length>0 and length<=64 and
    (explode as $c |
      (($c[0]>=48 and $c[0]<=57) or ($c[0]>=97 and $c[0]<=122)) and
      all($c[]; (.>=48 and .<=57) or (.>=97 and .<=122) or .==45));
  def digest:
    type=="string" and length==71 and startswith("sha256:") and
    (.[7:] | explode | all(.[]; (.>=48 and .<=57) or (.>=97 and .<=102)));
  def digits: type=="string" and length>0 and (explode | all(.[]; .>=48 and .<=57));
  def semver:
    if type!="string" then false else
      . as $v |
      ($v|split("+")) as $plus |
      ($v|split("+")[0]|split("-")[0]|split(".")) as $core |
      ($core|join(".")) as $base |
      ($v|explode|all(.[];
        (.>=48 and .<=57) or (.>=65 and .<=90) or (.>=97 and .<=122) or .==43 or .==45 or .==46)) and
      ($plus|length)<=2 and all($plus[]; length>0) and
      ($core|length)==3 and all($core[]; digits) and
      ($v==$base or ((($v|startswith($base+"-")) or ($v|startswith($base+"+"))) and ($v|length)>($base|length)+1))
    end;
  length>0 and ([.[].id]|unique|length)==length and
  all(.[]; (.id|skill_id) and .path==("skills/"+.id) and
  (.version|semver) and (.treeDigest|digest))' >/dev/null || fail 'unsafe package record'
requested="$incoming"
hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d ' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d ' ' -f1
  else fail 'SHA256 tool is required'; fi
}
hash_tree() (
  directory="$1"
  if [ -n "${ZSETUP_BIN:-}" ]; then
    [ -x "$ZSETUP_BIN" ] || fail 'configured zsetup is not executable'
    "$ZSETUP_BIN" checksum-tree "$directory"
    exit $?
  fi
  # Source-tree/developer fallback. Generated online packages always set
  # ZSETUP_BIN and therefore do not require these host utilities.
  for tool in find sort; do command -v "$tool" >/dev/null 2>&1 || fail "prepare $tool for source-tree installation"; done
  [ -d "$directory" ] || exit 1
  [ -z "$(find -H "$directory" -type l -print)" ] || exit 1
  cd -- "$directory"
  records="$(find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    printf '%s  %s\n' "$(hash_file "$file")" "${file#./}"
  done)"
  if command -v sha256sum >/dev/null 2>&1; then digest="$(printf '%s\n' "$records" | sha256sum)"
  else digest="$(printf '%s\n' "$records" | shasum -a 256)"; fi
  printf 'sha256:%s\n' "${digest%% *}"
)
release_id="${KAI_SKILLS_RELEASE:-$(jq -r '.version // empty' "$catalog")}"
case "$release_id" in ''|*[!0-9A-Za-z._+-]*) fail 'invalid release identity' ;; esac
state_file="$target/.linkease-skills/business-state.json"
empty='{"schemaVersion":2,"packages":{},"selections":{}}'
load_state() {
  [ ! -L "$target/.linkease-skills" ] && [ ! -L "$state_file" ] || fail 'ownership state is aliased'
  if [ -f "$state_file" ]; then state="$(jq -ce . "$state_file")" || fail 'invalid ownership state'
  else state="$empty"; fi
  printf '%s' "$state" | jq -e '
    def skill_id:
      type=="string" and length>0 and length<=64 and
      (explode as $c |
        (($c[0]>=48 and $c[0]<=57) or ($c[0]>=97 and $c[0]<=122)) and
        all($c[]; (.>=48 and .<=57) or (.>=97 and .<=122) or .==45));
    def digest:
      type=="string" and length==71 and startswith("sha256:") and
      (.[7:] | explode | all(.[]; (.>=48 and .<=57) or (.>=97 and .<=102)));
    def digits: type=="string" and length>0 and (explode | all(.[]; .>=48 and .<=57));
    def semver:
      if type!="string" then false else
        . as $v | ($v|split("+")) as $plus |
        ($v|split("+")[0]|split("-")[0]|split(".")) as $core |
        ($core|join(".")) as $base |
        ($v|explode|all(.[];
          (.>=48 and .<=57) or (.>=65 and .<=90) or (.>=97 and .<=122) or .==43 or .==45 or .==46)) and
        ($plus|length)<=2 and all($plus[]; length>0) and
        ($core|length)==3 and all($core[]; digits) and
        ($v==$base or ((($v|startswith($base+"-")) or ($v|startswith($base+"+"))) and ($v|length)>($base|length)+1))
      end;
    def selection_key:
      type=="string" and length>0 and
      (explode|all(.[]; (.>=48 and .<=57) or (.>=97 and .<=122) or .==45 or .==58 or .==64));
    def release_id:
      type=="string" and length>0 and
      (explode|all(.[];
        (.>=48 and .<=57) or (.>=65 and .<=90) or (.>=97 and .<=122) or .==43 or .==45 or .==46 or .==95));
    .schemaVersion==2 and (.packages|type)=="object" and (.selections|type)=="object" and
    all(.packages|to_entries[]; (.key|skill_id) and (.value.treeDigest|digest) and
      (.value.version|semver) and
      (.value.installMode=="copy" or .value.installMode=="symlink") and (.value.sourcePath|type)=="string") and
    (.packages as $packages | .selections as $selections |
      all($selections|to_entries[]; (.key|selection_key) and
        ((.value.consumer // "generic")|IN("codex","claude","opencode","generic")) and
        ((.value.scope // "user")|IN("user","project")) and
        ((.value.release // "legacy")|release_id) and
        (.value.members|type)=="array" and (.value.members|length)>0 and
        all(.value.members[]; . as $m | $packages[$m.id]!=null and $packages[$m.id].version==$m.version and $packages[$m.id].treeDigest==$m.treeDigest)) and
      all($packages|keys[]; . as $id | any($selections[].members[];.id==$id)))' >/dev/null || fail 'invalid ownership records or selection relationships'
}
import_legacy_state() {
  incoming="$requested"; legacy_desired='[]'; legacy_manifests='[]'; legacy_virtual_keys='[]'
  for legacy_file in "$target"/.linkease-skills/*.json; do
    [ -f "$legacy_file" ] || continue
    [ "$legacy_file" != "$state_file" ] || continue
    [ ! -L "$legacy_file" ] || fail 'legacy ownership is aliased'
    legacy_id="$(jq -er '.presetId|select(type=="string")' "$legacy_file")" || fail 'unknown legacy ownership file is preserved'
    safe_id "$legacy_id"
    [ "$(basename "$legacy_file")" = "$legacy_id.json" ] || fail 'legacy ownership filename mismatch'
    legacy_preset="$(jq -ce --arg id "$legacy_id" '.presets[]|select(.id==$id)' "$root/catalog.json")" || fail 'unknown legacy preset is preserved'
    legacy_platform="$(printf '%s' "$legacy_preset" | jq -r .platform)"
    legacy_mode="$(printf '%s' "$legacy_preset" | jq -r .mode)"
    legacy_key="system:$legacy_platform:$legacy_mode"
    printf '%s' "$state" | jq -e --arg key "$legacy_key" '.selections|has($key)|not' >/dev/null || fail 'legacy and modern ownership disagree for the same system selection'
    jq -e --arg id "$legacy_id" '
      def skill_id:
        type=="string" and length>0 and length<=64 and
        (explode as $c |
          (($c[0]>=48 and $c[0]<=57) or ($c[0]>=97 and $c[0]<=122)) and
          all($c[]; (.>=48 and .<=57) or (.>=97 and .<=122) or .==45));
      def digest:
        type=="string" and length==71 and startswith("sha256:") and
        (.[7:] | explode | all(.[]; (.>=48 and .<=57) or (.>=97 and .<=102)));
      .schemaVersion==1 and .presetId==$id and (.skills|type)=="array" and
      all((.skills+(.resources//[]))[]; (.name|skill_id) and (.treeDigest|digest))' "$legacy_file" >/dev/null || fail 'invalid legacy ownership record'
    legacy_members='[]'
    # Validate all old bytes before replacing even one package or ownership file.
    legacy_rows="$(jq -r '(.skills+(.resources//[]))[]|[.name,.treeDigest]|@tsv' "$legacy_file")"
    while IFS="$(printf '\t')" read -r legacy_name legacy_digest; do
      [ -n "$legacy_name" ] || continue
      [ "$(hash_tree "$target/$legacy_name")" = "$legacy_digest" ] || fail "modified legacy package $legacy_name is preserved"
      legacy_record="$(printf '%s' "$state" | jq -c --arg id "$legacy_name" '.packages[$id] // null')"
      if [ "$legacy_record" != null ]; then
        [ "$(printf '%s' "$legacy_record" | jq -r .treeDigest)" = "$legacy_digest" ] || fail 'overlapping legacy ownership content conflict'
      else
        legacy_install_mode=copy; legacy_source=
        if [ -L "$target/$legacy_name" ]; then legacy_install_mode=symlink; legacy_source="$(readlink "$target/$legacy_name")"; fi
        legacy_record="$(jq -cn --arg digest "$legacy_digest" --arg mode "$legacy_install_mode" --arg source "$legacy_source" '{version:"0.0.0-legacy",treeDigest:$digest,installMode:$mode,sourcePath:$source,legacyImported:true}')"
        state="$(printf '%s' "$state" | jq -c --arg id "$legacy_name" --argjson record "$legacy_record" '.packages[$id]=$record')"
      fi
      legacy_members="$(printf '%s' "$legacy_members" | jq -c --arg id "$legacy_name" --argjson record "$legacy_record" '.+[{id:$id,version:$record.version,treeDigest:$record.treeDigest}]')"
    done <<EOF
$legacy_rows
EOF
    state="$(printf '%s' "$state" | jq -c --arg key "$legacy_key" --arg p "$legacy_platform" --arg m "$legacy_mode" --arg c "$consumer" --arg s "$scope" --arg r "$release_id" --argjson members "$legacy_members" '.selections[$key]={platform:$p,mode:$m,consumer:$c,scope:$s,release:$r,members:$members}')"
    legacy_virtual_keys="$(printf '%s' "$legacy_virtual_keys" | jq -c --arg key "$legacy_key" '.+[$key]')"
    if [ "$action" = uninstall ]; then
      if [ "$legacy_key" = "$selection" ]; then
        legacy_manifests="$(printf '%s' "$legacy_manifests" | jq -c --arg id "$legacy_id" '.+[$id]')"
      fi
      continue
    fi
    legacy_lock="$root/bundles/$legacy_platform-all-$legacy_mode.json"
    [ -f "$legacy_lock" ] || fail 'full system collection required to migrate this legacy preset'
    legacy_new="$(jq -ce --slurpfile catalog "$catalog" '.members|map(. as $m|[$catalog[0].skills[]|select(.id==$m.id and .version==$m.version and .treeDigest==$m.treeDigest)]|if length==1 then .[0] else error("missing legacy upgrade member") end)' "$legacy_lock")" || fail 'legacy migration source is incomplete'
    legacy_desired="$(printf '%s' "$legacy_desired" | jq -c --arg key "$legacy_key" --argjson members "$legacy_new" '.+[{key:$key,members:$members}]')"
    legacy_manifests="$(printf '%s' "$legacy_manifests" | jq -c --arg id "$legacy_id" '.+[$id]')"
    incoming="$(printf '%s' "$incoming" | jq -c --argjson members "$legacy_new" '.+$members|unique_by(.id)')"
  done
}
verify_and_plan() {
  load_state
  if [ "$action" = uninstall ] && ! printf '%s' "$state" | jq -e --arg key "$selection" '.selections|has($key)' >/dev/null; then
    case "$selection" in
      skill:*|bundle:*) incoming="$requested"; legacy_desired='[]'; legacy_manifests='[]'; legacy_virtual_keys='[]'; return 0 ;;
    esac
  fi
  import_legacy_state
  printf '%s' "$state" | jq -r '.packages|to_entries[]|[.key,.value.treeDigest]|@tsv' | while IFS="$(printf '\t')" read -r id expected; do
    actual="$(hash_tree "$target/$id")" || fail "owned package $id is missing or aliased"
    [ "$actual" = "$expected" ] || fail "user-modified package $id is preserved"
    mode="$(printf '%s' "$state" | jq -r --arg id "$id" '.packages[$id].installMode')"
    if [ "$mode" = symlink ]; then
      source_path="$(printf '%s' "$state" | jq -r --arg id "$id" '.packages[$id].sourcePath')"
      [ -L "$target/$id" ] && [ "$(readlink "$target/$id")" = "$source_path" ] || fail "changed owned symlink $id is preserved"
    else [ ! -L "$target/$id" ] || fail "owned copy $id was replaced with a symlink"; fi
  done
  if [ "$action" = upgrade ]; then
    printf '%s' "$state" | jq -e --arg key "$selection" '.selections|has($key)' >/dev/null || fail 'selection is not installed'
  fi
  if [ "$action" = uninstall ]; then next="$(printf '%s' "$state" | jq -c --arg key "$selection" 'del(.selections[$key])')"
  else
    printf '%s' "$incoming" | jq -r '.[]|[.id,.treeDigest]|@tsv' | while IFS="$(printf '\t')" read -r id expected; do
      source="$root/skills/$id"
      [ ! -L "$source" ] || fail "source package $id is aliased"
      actual="$(hash_tree "$source")" || fail "invalid source package $id"
      [ "$actual" = "$expected" ] || fail "source digest mismatch $id"
      version="$(printf '%s' "$incoming" | jq -r --arg id "$id" '.[]|select(.id==$id)|.version')"
      jq -e --arg id "$id" --arg version "$version" '.id==$id and .version==$version' "$source/skill-package.json" >/dev/null || fail "source package identity/version mismatch $id"
      if [ -e "$target/$id" ] || [ -L "$target/$id" ]; then
        printf '%s' "$state" | jq -e --arg id "$id" '.packages|has($id)' >/dev/null || fail "unowned package $id is preserved"
        previous="$(printf '%s' "$state" | jq -r --arg id "$id" '.packages[$id].treeDigest')"
        if [ "$previous" != "$expected" ]; then
          legacy_imported="$(printf '%s' "$state" | jq -r --arg id "$id" '.packages[$id].legacyImported // false')"
          [ "$action" = upgrade ] || [ "$legacy_imported" = true ] || fail "version/content conflict for $id; explicit upgrade required"
          others="$(printf '%s' "$state" | jq -c --arg id "$id" --arg key "$selection" '[.selections|to_entries[]|select(.key!=$key and any(.value.members[];.id==$id))|.key]')"
          [ "$others" = '[]' ] || [ "$update_shared" = 1 ] || [ "$legacy_imported" = true ] || fail "shared conflict $id affects $others; use a coherent --upgrade --update-shared"
        fi
      fi
    done
  fi
}
build_plan() {
verify_and_plan
# The state reducer is kept explicit so uninstall never needs source payloads.
state_before_migration="$state"
state="$(printf '%s' "$state" | jq -c --argjson migrated "$legacy_desired" 'reduce $migrated[] as $m (.;.selections[$m.key].members=($m.members|map({id,version,treeDigest})))')"
if [ "$action" = uninstall ]; then
  next="$(printf '%s' "$state" | jq -c --arg key "$selection" 'del(.selections[$key])')"
else
  next="$(printf '%s' "$state" | jq -c --arg key "$selection" --arg p "$platform" --arg m "$usage_mode" --arg c "$consumer" --arg s "$scope" --arg r "$release_id" --arg mode "$install_mode" --arg root "$root" --argjson members "$incoming" --argjson requested "$requested" --argjson shared "$update_shared" '
    if $shared==1 then .selections |= with_entries(.value.members |= map(. as $old | ($members|map(select(.id==$old.id))|.[0]) // $old)) else . end |
    .selections[$key]={platform:$p,mode:$m,consumer:$c,scope:$s,release:$r,members:($requested|map({id,version,treeDigest}))} |
    reduce $members[] as $p (. ; if .packages[$p.id].treeDigest==$p.treeDigest and .packages[$p.id].version==$p.version then . else
      .packages[$p.id]={version:$p.version,treeDigest:$p.treeDigest,installMode:$mode,sourcePath:($root+"/skills/"+$p.id)} end)')"
fi
state="$state_before_migration"
next="$(printf '%s' "$next" | jq -c '([.selections[].members[].id]|unique) as $ids|.packages|=with_entries(select(.key as $id|$ids|index($id)))')"
removed="$(printf '%s' "$state" | jq -c --argjson next "$next" '[.packages|keys[]|select(. as $id|$next.packages|has($id)|not)]')"
plan_packages="$incoming"
if [ "$action" = uninstall ]; then
  plan_packages="$(printf '%s' "$state" | jq -c --arg key "$selection" '.selections[$key].members // []')"
  # Other old presets retain their v1 manifests and shared files. Their temporary
  # planning records must not become modern owners of unconverted payloads.
  next="$(printf '%s' "$next" | jq -c --argjson old "$legacy_virtual_keys" '
    .selections |= with_entries(select(.key as $key|$old|index($key)|not)) |
    ([.selections[].members[].id]|unique) as $ids | .packages |= with_entries(select(.key as $id|$ids|index($id)))')"
fi
plan="$(printf '%s' "$plan_packages" | jq -c --arg key "$selection" --arg action "$action" --arg target "$target" --arg c "$consumer" --arg s "$scope" --arg r "$release_id" --argjson removed "$removed" --argjson migrated "$legacy_manifests" '{schemaVersion:1,selection:$key,action:$action,destination:$target,consumer:$c,scope:$s,release:$r,packages:map({id,version,treeDigest}),removed:$removed,migratedPresets:$migrated,programOperations:[],serviceOperations:false}')"
}
build_plan
if [ "$dry" = 1 ]; then
  if [ "$json" = 1 ]; then printf '%s\n' "$plan"; else printf '%s\n' "$plan" | jq -r '"selection="+.selection,"action="+.action,"destination="+.destination,(.packages[]|"skill="+.id+" version="+.version+" digest="+.treeDigest),(.removed[]|"remove="+.)'; fi
  exit 0
fi
if [ "$action" = uninstall ] && [ "$state" = "$next" ] && [ "$legacy_manifests" = '[]' ]; then
  if [ "$json" = 1 ]; then printf '%s' "$plan" | jq '.+{status:"passed",reused:true}'; else echo "ok: selection=$selection already absent"; fi
  exit 0
fi
parent="$(dirname "$target")"; mkdir -p "$parent"
parent="$(CDPATH= cd -- "$parent" && pwd -P)"; target="$parent/$(basename "$target")"
state_file="$target/.linkease-skills/business-state.json"
lock_dir="$parent/.$(basename "$target").linkease-business-lock"
pause_for_test() {
  [ "${LINKEASE_BUSINESS_TEST_PAUSE_AT:-}" = "$1" ] || return 0
  marker="${LINKEASE_BUSINESS_TEST_PAUSE_FILE:?pause test requires an explicit marker}"
  : > "$marker.ready"
  attempt=0
  while [ ! -e "$marker.release" ]; do
    attempt=$((attempt+1)); [ "$attempt" -lt 1000 ] || fail 'test pause timed out'
    sleep 0.01
  done
}
pause_for_test before-lock
recover_lock() {
  [ -d "$lock_dir" ] && [ ! -L "$lock_dir" ] && [ -f "$lock_dir/owner.json" ] && [ ! -L "$lock_dir/owner.json" ] || fail 'unknown or aliased destination lock is preserved'
  owner="$(jq -ce --arg target "$target" '.schemaVersion==1 and .target==$target and (.pid|type)=="number" and .pid>1 and (.host|type)=="string"' "$lock_dir/owner.json")" || fail 'invalid destination lock is preserved'
  owner_pid="$(jq -r .pid "$lock_dir/owner.json")"
  owner_host="$(jq -r .host "$lock_dir/owner.json")"
  [ "$owner_host" = "$(uname -n)" ] || fail 'destination lock belongs to another host'
  if kill -0 "$owner_pid" 2>/dev/null; then fail 'another live installer owns this destination'; fi
  mkdir "$lock_dir/recovery" 2>/dev/null || fail 'another recovery owns this destination'
  abandoned="$(jq -r '.transaction // ""' "$lock_dir/owner.json")"
  if [ -n "$abandoned" ]; then
    [ "$(dirname "$abandoned")" = "$parent" ] && [ ! -L "$abandoned" ] || fail 'unsafe recovery transaction path'
    case "$(basename "$abandoned")" in .linkease-business-transaction.*) ;; *) fail 'unknown recovery transaction is preserved' ;; esac
    if [ ! -e "$target" ] && [ -d "$abandoned/previous" ]; then
      mv "$abandoned/previous" "$target"
    elif [ -d "$abandoned/previous" ]; then
      [ -f "$target/.linkease-skills/business-state.json" ] && cmp -s "$target/.linkease-skills/business-state.json" "$abandoned/expected-state.json" || fail 'ambiguous committed transaction is preserved'
    fi
    [ ! -d "$abandoned" ] || rm -rf "$abandoned"
  fi
  rm -f "$lock_dir/owner.json"
  rmdir "$lock_dir/recovery" "$lock_dir"
}
if ! mkdir "$lock_dir" 2>/dev/null; then
  recover_lock
  mkdir "$lock_dir" 2>/dev/null || fail 'destination became busy after recovery; retry'
fi
jq -n --argjson pid "$$" --arg target "$target" --arg host "$(uname -n)" '{schemaVersion:1,pid:$pid,target:$target,host:$host}' > "$lock_dir/owner.json"
transaction= previous= swapped=0
cleanup() {
  if [ ! -e "$target" ] && [ -n "$previous" ] && [ -d "$previous" ]; then
    if ! mv "$previous" "$target"; then echo "failed: recovery retained at $transaction" >&2; return; fi
  fi
  [ -z "$transaction" ] || rm -rf "$transaction"
  rm -f "$lock_dir/owner.json"
  rmdir "$lock_dir" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
# Re-read ownership under the lock. A pre-lock plan must never overwrite a winner.
build_plan
transaction="$(mktemp -d "$parent/.linkease-business-transaction.XXXXXX")"
jq --arg transaction "$transaction" '.+{transaction:$transaction}' "$lock_dir/owner.json" > "$lock_dir/owner.next"
mv "$lock_dir/owner.next" "$lock_dir/owner.json"
printf '%s\n' "$next" > "$transaction/expected-state.json"
stage="$transaction/next"; previous="$transaction/previous"; mkdir "$stage"
[ ! -d "$target" ] || cp -R "$target"/. "$stage"/
printf '%s' "$removed" | jq -r '.[]' | while IFS= read -r id; do rm -rf "$stage/$id"; done
if [ "$action" != uninstall ]; then
  printf '%s' "$incoming" | jq -r '.[].id' | while IFS= read -r id; do
    if [ -e "$stage/$id" ] || [ -L "$stage/$id" ]; then
      existing="$(printf '%s' "$state" | jq -r --arg id "$id" '.packages[$id].treeDigest // ""')"
      desired="$(printf '%s' "$next" | jq -r --arg id "$id" '.packages[$id].treeDigest')"
      [ "$existing" != "$desired" ] || continue
    fi
    rm -rf "$stage/$id"
    case "$install_mode" in copy) cp -R "$root/skills/$id" "$stage/$id" ;; symlink) ln -s "$root/skills/$id" "$stage/$id" ;; esac
    expected="$(printf '%s' "$next" | jq -r --arg id "$id" '.packages[$id].treeDigest')"
    [ "$(hash_tree "$stage/$id")" = "$expected" ] || fail "staged digest mismatch $id"
  done
fi
mkdir -p "$stage/.linkease-skills"
printf '%s' "$legacy_manifests" | jq -r '.[]' | while IFS= read -r id; do rm -f "$stage/.linkease-skills/$id.json"; done
printf '%s\n' "$next" > "$stage/.linkease-skills/business-state.json"
pause_for_test before-swap
[ "${LINKEASE_BUSINESS_TEST_FAIL:-}" != before-swap ] || fail 'injected pre-swap failure'
if [ -d "$target" ]; then mv "$target" "$previous"; swapped=1; fi
pause_for_test after-old-move
[ "${LINKEASE_BUSINESS_TEST_FAIL:-}" != after-old-move ] || fail 'injected swap failure'
mv "$stage" "$target"
swapped=0
rm -rf "$transaction"
transaction=
rm -f "$lock_dir/owner.json"
rmdir "$lock_dir"
trap - EXIT HUP INT TERM
if [ "$json" = 1 ]; then printf '%s\n' "$plan" | jq '.+{status:"passed"}'; else echo "ok: $action selection=$selection destination=$target"; fi
