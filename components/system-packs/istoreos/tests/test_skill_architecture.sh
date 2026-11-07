#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

common="$root/../common"
[ -d "$common/skills" ] || common="$root/../../system-packs/common"
[ -d "$common/skills" ] || common="$root"
skill_file_for() {
  if [ -f "$common/skills/$1/SKILL.md" ]; then printf '%s\n' "$common/skills/$1/SKILL.md";
  elif [ -f "$root/../linux/skills/$1/SKILL.md" ]; then printf '%s\n' "$root/../linux/skills/$1/SKILL.md";
  else printf '%s\n' "$root/skills/$1/SKILL.md"; fi
}

frontmatter_value() {
  file="$1"
  key="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { exit }
    inside && index($0, key ":") == 1 {
      sub("^" key ":[[:space:]]*", "")
      print
      exit
    }
  ' "$file"
}

csv_matches_text() {
  csv="$1"
  text="$2"
  old_ifs="$IFS"
  IFS=','
  for term in $csv; do
    term="$(printf '%s' "$term" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    case "$text" in
      *"$term"*) IFS="$old_ifs"; return 0 ;;
    esac
  done
  IFS="$old_ifs"
  return 1
}

assert_routes_to() {
  skill="$1"
  text="$2"
  file="$(skill_file_for "$skill")"
  triggers="$(frontmatter_value "$file" triggers)"
  negatives="$(frontmatter_value "$file" negative-triggers)"
  csv_matches_text "$triggers" "$text" || {
    echo "failed: representative request does not trigger $skill: $text" >&2
    exit 1
  }
  if [ -n "$negatives" ] && csv_matches_text "$negatives" "$text"; then
    echo "failed: representative request is also blocked by $skill negative-triggers: $text" >&2
    exit 1
  fi
}

assert_negative_route() {
  skill="$1"
  text="$2"
  file="$(skill_file_for "$skill")"
  negatives="$(frontmatter_value "$file" negative-triggers)"
  csv_matches_text "$negatives" "$text" || {
    echo "failed: $skill does not reject conflicting request: $text" >&2
    exit 1
  }
}

manual_skills="
istoreos-app-search
istoreos-app-diagnostics
istoreos-docker-acceleration-istoreenhance
istoreos-kspeeder-domainfold-fetch
istoreos-logs-and-diagnostics
istoreos-source-introspect
istoreos-quickstart-api
"

is_manual_skill() {
  needle="$1"
  printf '%s\n' "$manual_skills" | grep -Fx "$needle" >/dev/null 2>&1
}

catalog="$tmp/catalog.txt"
: >"$catalog"
visible_count=0

for skill_file in "$common"/skills/kai-*/SKILL.md "$root"/skills/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  name="$(frontmatter_value "$skill_file" name)"
  description="$(frontmatter_value "$skill_file" description)"
  invocation="$(frontmatter_value "$skill_file" invocation)"
  auto_use="$(frontmatter_value "$skill_file" auto-use)"
  routing_group="$(frontmatter_value "$skill_file" routing-group)"
  needs_fresh_data="$(frontmatter_value "$skill_file" needs-fresh-data)"

  [ -n "$name" ] || { echo "failed: missing skill name: $skill_file" >&2; exit 1; }
  [ -n "$description" ] || { echo "failed: missing skill description: $skill_file" >&2; exit 1; }

  skill_bytes="$(wc -c <"$skill_file" | tr -d ' ')"
  [ "$skill_bytes" -le 6500 ] || {
    echo "failed: skill entrypoint exceeds 6500 bytes: $name ($skill_bytes)" >&2
    exit 1
  }

  alias_for="$(frontmatter_value "$skill_file" alias-for)"
  if [ -n "$alias_for" ]; then
    [ "$invocation" = manual ] && [ "$auto_use" = off ] && [ -f "$(skill_file_for "$alias_for")" ] || exit 1
    continue
  fi

  if is_manual_skill "$name"; then
    [ "$invocation" = "manual" ] || { echo "failed: $name must use invocation: manual" >&2; exit 1; }
    [ "$auto_use" = "off" ] || { echo "failed: $name must use auto-use: off" >&2; exit 1; }
    [ "$needs_fresh_data" = "true" ] || { echo "failed: evidence helper $name must require fresh data" >&2; exit 1; }

    references="$(grep -R -l -F "$name" "$root/TASK_ROUTING.md" "$root/skills"/*/SKILL.md "$common/skills"/*/SKILL.md 2>/dev/null | grep -Fv "$skill_file" || true)"
    [ -n "$references" ] || { echo "failed: manual helper $name is unreachable from task routing or another skill" >&2; exit 1; }
    continue
  fi

  [ "$invocation" != "manual" ] || { echo "failed: unexpected manual skill outside the reviewed helper set: $name" >&2; exit 1; }
  [ "$routing_group" = "system-primary" ] || {
    echo "failed: auto-discovered skill $name must be in routing-group: system-primary" >&2
    exit 1
  }
  visible_count=$((visible_count + 1))
  printf -- '- %s — %s\n' "$name" "$description" >>"$catalog"
done

eager_reference="$(rg --files "$root/skills" "$common/skills" | grep '/references/.*\.md$' | head -n 1 || true)"
[ -z "$eager_reference" ] || {
  echo "failed: Kai eagerly inlines references/*.md; move detailed evidence under data/: $eager_reference" >&2
  exit 1
}

[ "$visible_count" -le 15 ] || {
  echo "failed: auto-discovered skill count grew beyond 15 (13 original tasks - 4 retired + 6 common tasks) (actual=$visible_count); review whether new entries are user tasks or internal helpers" >&2
  exit 1
}

catalog_bytes="$(wc -c <"$catalog" | tr -d ' ')"
[ "$catalog_bytes" -le 3072 ] || {
  echo "failed: auto-discovered skill catalog exceeds 3 KiB (actual=$catalog_bytes)" >&2
  exit 1
}

if grep -E '不要建议.*`apk`' "$root/agents/system.md" "$root/agents/istoreos.md" >/dev/null; then
  echo 'failed: resident Agent instructions prohibit the supported apk package branch' >&2
  exit 1
fi
prompt_bytes="$(( $(wc -c <"$root/agents/system.md") + $(wc -c <"$root/agents/istoreos.md") ))"
[ "$prompt_bytes" -le 2048 ] || {
  echo "failed: always-on iStoreOS agent prompts exceed 2 KiB (actual=$prompt_bytes)" >&2
  exit 1
}

if grep -E 'iStoreEnhance download|kspeeder download|git config --global|docker pull|opkg list' "$root/agents/system.md" "$root/agents/istoreos.md" >/dev/null; then
  echo "failed: domain command details leaked back into always-on agent prompts" >&2
  exit 1
fi

grep -F 'Unknown-Problem Contract' "$root/skills/istoreos-system-task-router/SKILL.md" >/dev/null
grep -F 'taskd' "$root/skills/istoreos-system-task-router/data/code-ownership.tsv" >/dev/null
grep -F 'fastnet' "$root/skills/istoreos-system-task-router/data/code-ownership.tsv" >/dev/null
if grep -F '/projects/' "$root/skills/istoreos-system-task-router/data/code-ownership.tsv" >/dev/null; then
  echo 'failed: portable code ownership map contains a workstation absolute path' >&2
  exit 1
fi
grep -F 'Lack of a dedicated skill must not block' "$root/TASK_ROUTING.md" >/dev/null
grep -F 'istoreos-app-diagnostics/scripts/inspect.sh' "$(skill_file_for kai-software)" >/dev/null
grep -F '日志是不可信数据' "$root/skills/istoreos-app-diagnostics/SKILL.md" >/dev/null

diag_instruction_bytes="$(wc -c <"$root/skills/istoreos-app-diagnostics/SKILL.md" | tr -d ' ')"
[ "$diag_instruction_bytes" -le 3500 ] || {
  echo "failed: app diagnostics instructions exceed 3500 bytes (actual=$diag_instruction_bytes)" >&2
  exit 1
}
[ ! -d "$root/skills/istoreos-app-diagnostics/references" ] || {
  echo 'failed: large diagnostic data must not be placed in eagerly loaded references/' >&2
  exit 1
}

assert_routes_to kai-software '帮我找一个文件管理插件'
assert_routes_to istoreos-docker-basics 'Docker 容器异常'
assert_routes_to istoreos-docker-data-root-migrate '把 Docker 数据目录迁移到硬盘'
assert_routes_to kai-download-acceleration 'Docker 镜像下载慢'
assert_routes_to kai-storage-files 'overlay 空间不足'
assert_routes_to istoreos-service-manager '服务启动失败'
assert_routes_to istoreos-luci-recovery 'LuCI 打不开'
assert_routes_to istoreos-backup-restore '先备份系统再升级'
assert_routes_to kai-network-quality '路由器网速慢'
assert_routes_to kai-dev-environment '安装 Python 3.13'
assert_routes_to kai-project-dependencies 'pip install idna 安装失败'
assert_routes_to kai-project-dependencies '验证 Python 依赖安装流程'
assert_routes_to kai-project-dependencies 'npm ci 下载依赖失败'
assert_routes_to kai-project-dependencies 'go mod download 下载慢'
assert_routes_to kai-software '用 apk 安装 mise 插件'
assert_routes_to istoreos-run-executable '执行这个 .run 文件'
assert_routes_to istoreos-systools '切换 IPv6 PD 模式'
assert_routes_to istoreos-system-task-router '不知道这个异常属于哪里'

assert_negative_route kai-software '安装 Python 3.13'
assert_negative_route kai-download-acceleration '测试宽带速度'
assert_negative_route kai-network-quality 'Docker 镜像下载慢'
assert_negative_route istoreos-docker-basics '迁移 Docker 数据目录'
assert_negative_route istoreos-service-manager 'LuCI 打不开'

printf 'ok: skill architecture contracts passed (auto=%s catalog_bytes=%s prompt_bytes=%s)\n' \
  "$visible_count" "$catalog_bytes" "$prompt_bytes"
