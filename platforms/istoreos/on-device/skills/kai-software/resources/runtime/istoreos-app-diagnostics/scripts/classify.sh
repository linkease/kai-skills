#!/bin/sh
set -eu

input="${1:-/dev/stdin}"
state_input="${2:-}"
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
rules="${ISTORE_DIAG_RULES_FILE:-$script_dir/../data/failure-rules.tsv}"

value_of() {
  key="$1"
  awk -F '\t' -v key="$key" '$1 == key { sub(/^[^\t]*\t/, ""); print; exit }' "$input"
}

state="$(value_of state)"
correlation="$(value_of correlation)"
exit_code="$(value_of exit_code)"
age="$(value_of age_seconds)"
log="$(sed -n '/^--LOG--$/,$p' "$input" | sed '1d')"

outcome=unknown
code=NO_RECENT_TASK
confidence=low
  next_skill=
  next_skill=istoreos-logs-and-diagnostics
  summary='没有可归因于目标应用的近期 iStore 安装任务；请继续采集该应用的受限运行日志。'

if [ "$correlation" = mismatch ]; then
  code=TASK_APP_MISMATCH
  confidence=high
  summary='最近的 iStore 任务属于另一个应用，已拒绝错误归因。'
elif [ "$correlation" = exact ] && [ "$state" = running ]; then
  outcome=in_progress
  code=TASK_RUNNING
  confidence=high
  summary='目标应用的 iStore 任务仍在运行，暂不判定成功或失败。'
elif [ "$correlation" = exact ]; then
  case "$exit_code" in
    0)
      if printf '%s\n' "$log" | grep -Eiq 'warning|bad substitution|parse error|differs from the package version|collected errors'; then
        outcome=success_with_warnings
        code=LOG_WARNINGS
        confidence=medium
        summary='安装任务退出成功，但日志中存在需要复核的警告。'
      else
        outcome=success
        code=SUCCESS
        confidence=high
        summary='安装任务退出成功，未发现显著错误特征。'
      fi
      ;;
    ''|*[!0-9-]*)
      outcome=unknown
      code=EXIT_CODE_UNKNOWN
      confidence=low
      summary='无法取得安装任务退出码。'
      ;;
    *)
      outcome=package_install_failed
      code=OPKG_FAILED
      confidence=medium
      next_skill=kai-software
      summary='安装任务非零退出，但紧凑规则库未识别出更具体原因。'
      while IFS="$(printf '\t')" read -r rule_code rule_outcome rule_skill pattern; do
        case "$rule_code" in ''|'#'*) continue ;; esac
        if printf '%s\n' "$log" | grep -Eiq "$pattern"; then
          code="$rule_code"
          outcome="$rule_outcome"
          next_skill="$rule_skill"
          confidence=high
          case "$code" in
            DEPENDENCY_MISSING) summary='安装依赖无法满足。' ;;
            NO_SPACE) summary='目标文件系统空间不足。' ;;
            READ_ONLY_FILESYSTEM) summary='目标文件系统为只读。' ;;
            ARCH_UNSUPPORTED) summary='软件包与设备架构不兼容。' ;;
            DOWNLOAD_DNS_FAILED) summary='下载阶段域名解析失败。' ;;
            DOWNLOAD_TLS_FAILED) summary='下载阶段 TLS 证书或握手失败。' ;;
            HASH_MISMATCH) summary='下载的软件包校验值不匹配。' ;;
            POSTINST_FAILED) summary='软件包 postinst 阶段失败。' ;;
            AUTOCONF_FAILED) summary='iStore 自动配置阶段失败。' ;;
            DOCKER_PULL_FAILED) summary='Docker 镜像拉取失败。' ;;
            VOLUME_PERMISSION) summary='容器数据卷或挂载目录权限不足。' ;;
            PORT_CONFLICT) summary='容器需要的端口已被占用。' ;;
            CONTAINER_OOM) summary='容器或 Docker 进程发生内存不足。' ;;
          esac
          break
        fi
      done <"$rules"
      ;;
  esac
fi

if [ -n "$state_input" ] && [ "$correlation" = exact ] && [ "$state" = finished ] && [ "$exit_code" = 0 ]; then
  state_value() { awk -F '\t' -v key="$1" '$1 == key { print $2; exit }' "$state_input"; }
  package_installed="$(state_value package_installed)"
  autoconf_present="$(state_value autoconf_present)"
  target_path_available="$(state_value target_path_available)"
  init_script_present="$(state_value init_script_present)"
  istorec_present="$(state_value istorec_present)"
  service_state="$(state_value service_state)"
  container_state="$(state_value container_state)"
  autoconf_requested="$(value_of autoconf_requested)"
  enable_requested="$(value_of enable_requested)"
  if [ "$package_installed" = false ]; then
    outcome=package_install_failed
    code=APP_NOT_INSTALLED
    confidence=high
    next_skill=kai-software
    summary='任务退出成功，但设备当前未安装目标 meta 包。'
  elif [ "$autoconf_requested" = true ] && [ "$autoconf_present" = false ]; then
    outcome=autoconf_failed
    code=AUTOCONF_SCRIPT_MISSING
    confidence=high
    next_skill=istoreos-source-introspect
    summary='任务请求了自动配置，但设备上缺少对应 autoconf 脚本。'
  elif [ "$target_path_available" = false ]; then
    outcome=autoconf_failed
    code=TARGET_PATH_UNAVAILABLE
    confidence=high
    next_skill=kai-storage-files
    summary='自动配置使用的目标路径当前不可用。'
  elif [ "$enable_requested" = 0 ] && {
    { [ "$init_script_present" = true ] && [ -n "$service_state" ] && ! printf '%s\n' "$service_state" | grep -Eiq '(^|[^a-z])(running|active|up)([^a-z]|$)'; } ||
    { [ "$istorec_present" = true ] && [ -n "$container_state" ] && ! printf '%s\n' "$container_state" | grep -Eiq '^(running|up)$'; }
  }; then
    outcome=success
    code=EXPECTED_STOPPED
    confidence=high
    next_skill=
    summary='用户请求 enable=0，服务或容器停止属于预期状态。'
  elif [ "$enable_requested" = 1 ] && [ "$istorec_present" = true ] && [ -n "$container_state" ] && ! printf '%s\n' "$container_state" | grep -Eiq '^(running|up)$'; then
    outcome=runtime_failed
    code=CONTAINER_NOT_RUNNING
    confidence=high
    next_skill=istoreos-docker-basics
    summary='安装与自动配置已完成，但请求启用的容器当前未运行。'
  elif [ "$enable_requested" = 1 ] && [ "$init_script_present" = true ] && [ -n "$service_state" ] && ! printf '%s\n' "$service_state" | grep -Eiq '(^|[^a-z])(running|active|up)([^a-z]|$)'; then
    outcome=runtime_failed
    code=SERVICE_NOT_RUNNING
    confidence=high
    next_skill=istoreos-service-manager
    summary='安装与自动配置已完成，但请求启用的服务当前未运行。'
  fi
fi

case "$age" in
  ''|*[!0-9]*) ;;
  *)
    if [ "$age" -gt "${ISTORE_DIAG_STALE_SECONDS:-3600}" ] && [ "$confidence" = high ]; then
      confidence=medium
    fi
    ;;
esac

printf 'outcome\t%s\n' "$outcome"
printf 'primary_code\t%s\n' "$code"
printf 'confidence\t%s\n' "$confidence"
printf 'next_skill\t%s\n' "$next_skill"
printf 'summary\t%s\n' "$summary"
