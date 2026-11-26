#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
inspect="$root/skills/istoreos-app-diagnostics/scripts/inspect.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
command -v jq >/dev/null 2>&1 || { echo 'skip: jq required'; exit 0; }
export ISTORE_STORE_RESPONSE_FILE="$root/tests/fixtures/store-catalog.json"

make_case() {
  name="$1" app="$2" enable="$3" kind="$4" current="$5"
  case_root="$tmp/$name"
  mkdir -p "$case_root/rootfs/usr/lib/opkg" "$case_root/rootfs/usr/lib/opkg/meta" "$case_root/rootfs/usr/libexec/istorea" "$case_root/rootfs/run/istore-diag"
  printf 'Package: app-meta-%s\nStatus: install user installed\n\n' "$app" >"$case_root/rootfs/usr/lib/opkg/status"
  : >"$case_root/rootfs/usr/lib/opkg/meta/$app.json"
  : >"$case_root/rootfs/usr/libexec/istorea/$app.sh"
  if [ "$kind" = service ]; then
    mkdir -p "$case_root/rootfs/etc/init.d"
    : >"$case_root/rootfs/etc/init.d/$app"
    printf '%s\n' "$current" >"$case_root/rootfs/run/istore-diag/service-$app.state"
  else
    mkdir -p "$case_root/rootfs/usr/libexec/istorec"
    : >"$case_root/rootfs/usr/libexec/istorec/$app.sh"
    printf '%s\n' "$current" >"$case_root/rootfs/run/istore-diag/container-$app.state"
  fi
  printf '{"running":false,"start":1789173000,"stop":1789173001,"exit_code":0,"command":"is-opkg '\''AUTOCONF=%s enable=%s'\'' '\''install'\'' '\''app-meta-%s'\''"}\n' "$app" "$enable" "$app" >"$case_root/task-status.json"
  printf 'Installing app-meta-%s\nConfiguring app-meta-%s\n' "$app" "$app" >"$case_root/istore.log"
}

run_case() {
  name="$1" app="$2"; shift 2
  ISTORE_DIAG_ROOT="$tmp/$name/rootfs" \
  ISTORE_DIAG_TASK_STATUS_FILE="$tmp/$name/task-status.json" \
  ISTORE_DIAG_LOG_FILE="$tmp/$name/istore.log" ISTORE_DIAG_NOW=1789173400 \
    "$inspect" "$app" "$@"
}

make_case disabled-service demo-disabled 0 service stopped
run_case disabled-service demo-disabled >"$tmp/disabled.json"
jq -e '.result.outcome == "success" and .result.primary_code == "EXPECTED_STOPPED" and .next.skill == null and .task.enable_requested == 0' "$tmp/disabled.json" >/dev/null

make_case stopped-service demo-service 1 service stopped
run_case stopped-service demo-service >"$tmp/service.json"
jq -e '.result.outcome == "runtime_failed" and .result.primary_code == "SERVICE_NOT_RUNNING" and .next.skill == null' "$tmp/service.json" >/dev/null

make_case stopped-container demo-container 1 container exited
run_case stopped-container demo-container >"$tmp/container.json"
jq -e '.result.outcome == "runtime_failed" and .result.primary_code == "CONTAINER_NOT_RUNNING" and .next.skill == null' "$tmp/container.json" >/dev/null

# Precise evidence must not invoke the broader system-log fallback.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/logread" <<'EOF'
#!/bin/sh
: >"$ISTORE_DIAG_LOGREAD_MARKER"
echo 'demo-service unrelated fallback output'
EOF
chmod +x "$tmp/bin/logread"
ISTORE_DIAG_LOGREAD_MARKER="$tmp/logread.called" PATH="$tmp/bin:$PATH" run_case stopped-service demo-service --detail runtime >"$tmp/known-detail.json"
[ ! -e "$tmp/logread.called" ] || { echo 'failed: known evidence invoked logread' >&2; exit 1; }

# Missing task history keeps a generic, actionable path and requests only
# filtered, bounded system log evidence when detail is explicitly requested.
printf 'daemon.notice unrelated: secret=must-not-appear\n' >"$tmp/system.log"
printf 'daemon.err thirdparty: failed token=fixture-token https://example.test/a?token=fixture-query\n' >>"$tmp/system.log"
mkdir -p "$tmp/unknown/rootfs"
ISTORE_DIAG_ROOT="$tmp/unknown/rootfs" ISTORE_DIAG_TASK_STATUS_FILE=/dev/null ISTORE_DIAG_LOG_FILE=/dev/null \
ISTORE_DIAG_SYSTEM_LOG_FILE="$tmp/system.log" "$inspect" thirdparty --detail runtime >"$tmp/unknown.json"
jq -e '.result.outcome == "unknown" and .next.skill == null and (.detail.log_excerpt | contains("thirdparty"))' "$tmp/unknown.json" >/dev/null
if grep -E 'must-not-appear|fixture-token|fixture-query' "$tmp/unknown.json" >/dev/null; then
  echo 'failed: unknown-app fallback leaked unrelated or credential data' >&2
  exit 1
fi
[ "$(jq -r '.detail.log_excerpt' "$tmp/unknown.json" | wc -l)" -le 120 ]
[ "$(jq -r '.detail.log_excerpt' "$tmp/unknown.json" | wc -c)" -le 8192 ]

# The same target evidence produces byte-identical results through a fake
# remote shell boundary because this skill has no transport-specific branch.
run_case stopped-container demo-container >"$tmp/local.json"
ISTORE_DIAG_ROOT="$tmp/stopped-container/rootfs" \
ISTORE_DIAG_TASK_STATUS_FILE="$tmp/stopped-container/task-status.json" \
ISTORE_DIAG_LOG_FILE="$tmp/stopped-container/istore.log" ISTORE_DIAG_NOW=1789173400 \
  sh -c 'exec "$1" "$2"' fake-remote "$inspect" demo-container >"$tmp/remote.json"
cmp "$tmp/local.json" "$tmp/remote.json" >/dev/null

printf 'ok: app diagnostics runtime, bounded fallback, and transport-neutral contracts passed\n'
