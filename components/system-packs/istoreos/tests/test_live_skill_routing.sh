#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
credential_file=${DEEPSEEK_CREDENTIALS_FILE:-}
model=${DEEPSEEK_MODEL:-deepseek-v4-flash}
max_tokens=${DEEPSEEK_MAX_TOKENS:-512}
case_filter=${LIVE_ROUTE_CASE:-}

frontmatter_value() {
  awk -v wanted="$2" '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && index($0, wanted ":") == 1 {
      value = substr($0, length(wanted) + 2)
      sub(/^[[:space:]]+/, "", value)
      print value
      exit
    }
  ' "$1"
}

credential_value() {
  awk -v wanted="$2" '
    index($0, wanted "=") == 1 {
      value = substr($0, length(wanted) + 2)
      sub(/\r$/, "", value)
      gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", value)
      print value
      exit
    }
  ' "$1"
}

server=${DEEPSEEK_BASE_URL:-}
key=${DEEPSEEK_API_KEY:-}
if [ -n "$credential_file" ]; then
  [ -r "$credential_file" ] || {
    echo "failed: credential file is not readable" >&2
    exit 1
  }
  [ -n "$server" ] || server=$(credential_value "$credential_file" SERVER)
  [ -n "$key" ] || key=$(credential_value "$credential_file" KEY)
fi
[ -n "$server" ] || {
  echo "failed: set DEEPSEEK_BASE_URL or DEEPSEEK_CREDENTIALS_FILE" >&2
  exit 1
}
[ -n "$key" ] || {
  echo "failed: set DEEPSEEK_API_KEY or DEEPSEEK_CREDENTIALS_FILE" >&2
  exit 1
}

server=${server%/}
case "$server" in
  */v1) api="$server/chat/completions" ;;
  *) api="$server/v1/chat/completions" ;;
esac

catalog=
auto_names=
common="$root/../common"
[ -d "$common/skills" ] || common="$root/../../system-packs/common"
[ -d "$common/skills" ] || common="$root"
for file in "$common"/skills/kai-*/SKILL.md "$root"/skills/*/SKILL.md; do
  name=$(frontmatter_value "$file" name)
  description=$(frontmatter_value "$file" description)
  invocation=$(frontmatter_value "$file" invocation)
  [ "$invocation" = manual ] && continue
  [ -n "$name" ] || continue
  catalog="${catalog}${name}: ${description}
"
  auto_names="${auto_names}${name}
"
done

auto_json=$(printf '%b' "$auto_names" | jq -Rsc 'split("\n") | map(select(length > 0))')
auto_count=$(printf '%s' "$auto_json" | jq 'length')
[ "$auto_count" -eq 15 ] || {
  echo "failed: live routing expected 15 auto skills, got $auto_count" >&2
  exit 1
}

system_prompt=$(awk '1' "$root/agents/system.md" "$root/agents/istoreos.md")
system_prompt="${system_prompt}

Available skills:
${catalog}
For this routing test, call run_skill exactly once with the single best primary skill. Do not answer the user yet."

failed=0
total=0
while IFS='|' read -r expected prompt; do
  [ -n "$expected" ] || continue
  [ -z "$case_filter" ] || [ "$case_filter" = "$expected" ] || continue
  total=$((total + 1))
  payload=$(jq -cn \
    --arg model "$model" \
    --arg system "$system_prompt" \
    --arg user "$prompt" \
    --argjson max_tokens "$max_tokens" \
    --argjson names "$auto_json" \
    '{
      model: $model,
      messages: [
        {role: "system", content: $system},
        {role: "user", content: $user}
      ],
      tools: [{
        type: "function",
        function: {
          name: "run_skill",
          description: "Load one iStoreOS skill by name.",
          parameters: {
            type: "object",
            properties: {name: {type: "string", enum: $names}},
            required: ["name"],
            additionalProperties: false
          }
        }
      }],
      tool_choice: "required",
      temperature: 0,
      max_tokens: $max_tokens
    }')

  if ! response=$(curl -fsS --max-time 60 \
    -H "Authorization: Bearer $key" \
    -H 'Content-Type: application/json' \
    --data-binary "$payload" \
    "$api"); then
    echo "failed: live request failed for expected route $expected" >&2
    exit 1
  fi

  actual=$(printf '%s' "$response" | jq -r '
    .choices[0].message.tool_calls[0].function.arguments
    | (if type == "string" then fromjson else . end)
    | .name // empty
  ' 2>/dev/null || true)
  if [ "$actual" = "$expected" ]; then
    echo "ok: $expected"
  else
    echo "failed: expected $expected, got ${actual:-no-tool-call}" >&2
    failed=$((failed + 1))
  fi
done <<'CASES'
kai-tool-bootstrap|准备完整 jq 和开发工具引导，不要更改系统 curl
kai-software|帮我找一个文件管理插件
istoreos-docker-basics|Docker 容器反复退出，帮我检查容器状态和日志
istoreos-docker-data-root-migrate|把 Docker 数据目录迁移到外接硬盘
kai-download-acceleration|Docker 镜像下载很慢，怎么加速拉取
kai-project-dependencies|用已经安装的 Python 3.13.7 验证 Python 依赖安装流程，创建隔离 venv，安装 idna 并检查网关证据
istoreos-luci-recovery|LuCI 管理页面打不开，但 SSH 可以登录
kai-network-quality|宽带测速结果很差，检查延迟、丢包和上下行速度
kai-storage-files|overlay 空间不足，帮我选择持久化存储路径
istoreos-service-manager|一个 init.d 服务启动失败，帮我检查状态
istoreos-backup-restore|升级前备份系统配置，并说明如何恢复
istoreos-run-executable|检查并运行我上传的 .run 安装文件
kai-dev-environment|在 iStoreOS 上安装 Python 3.13
istoreos-systools|把 IPv6 模式从 relay 切换成 PD
istoreos-system-task-router|系统偶尔异常，但我不知道属于网络、存储还是服务，请先判断方向
CASES

[ "$failed" -eq 0 ] || {
  echo "failed: $failed of $total live routing cases did not select the expected primary skill" >&2
  exit 1
}
echo "ok: all $total live skill routing cases passed with $model"
