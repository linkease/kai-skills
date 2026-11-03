#!/bin/sh
set -eu

file="${1:-}"
confirm="${CONFIRM_RUN_EXEC:-}"
run_via_dotrun="${RUN_VIA_ISTORE_DOTRUN:-auto}" # auto|yes|no
backup_done="${CONFIRM_BACKUP_DONE:-}"
backup_skipped="${CONFIRM_BACKUP_SKIPPED:-}"

need() {
  echo "need-confirmation: $*" >&2
  exit 2
}

have() { command -v "$1" >/dev/null 2>&1; }

ts() { date +%Y%m%d-%H%M%S 2>/dev/null || echo now; }

run_logged() {
  # POSIX pipelines return tee's status; preserve the program's status separately.
  status_file="$(mktemp)"
  trap 'rm -f "$status_file"' EXIT HUP INT TERM
  (
    code=0
    "$@" 2>&1 || code=$?
    printf '%s\n' "$code" > "$status_file"
  ) | tee "$log"
  code="$(cat "$status_file")"
  rm -f "$status_file"
  trap - EXIT HUP INT TERM
  echo "log: $log" >&2
  return "$code"
}

if [ "$confirm" != "YES" ]; then
  need "this will execute a local .run file (risky). Recommended: run a full system backup first (istoreos-backup-restore). Rerun with CONFIRM_RUN_EXEC=YES."
fi

if [ "$backup_done" != "YES" ] && [ "$backup_skipped" != "YES" ]; then
  need "confirm backup status first: run a full system backup (istoreos-backup-restore), then rerun with CONFIRM_BACKUP_DONE=YES; or accept risk and rerun with CONFIRM_BACKUP_SKIPPED=YES."
fi

if [ -z "$file" ]; then
  echo "usage: $0 <FILE.run> [args...]" >&2
  exit 2
fi

shift || true

is_url() {
  case "${1:-}" in
    *://*) return 0 ;;
    *) return 1 ;;
  esac
}

fetch_if_url() {
  in="$1"
  if is_url "$in"; then
    skills_dir="$(resolve_skills_dir || true)"
    fetch="$skills_dir/istoreos-run-executable/scripts/fetch.sh"
    if [ ! -f "$fetch" ]; then
      need "fetch script not found: $fetch (ensure skills are installed)"
    fi
    sh "$fetch" "$in"
    return 0
  fi
  printf '%s\n' "$in"
}

resolve_skills_dir() {
  if [ -n "${KAIPLUS_SKILLS_DIR:-}" ] && [ -d "$KAIPLUS_SKILLS_DIR" ]; then
    printf '%s\n' "$KAIPLUS_SKILLS_DIR"
    return 0
  fi
  if [ -n "${KAIPLUS_HOME:-}" ] && [ -d "$KAIPLUS_HOME/config/skills" ]; then
    printf '%s\n' "$KAIPLUS_HOME/config/skills"
    return 0
  fi
  script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P || true)"
  if [ -n "$script_dir" ]; then
    script_skill_dir="$(dirname "$(dirname "$script_dir")")"
    skills_dir="$(dirname "$script_skill_dir")"
    if [ -d "$skills_dir" ]; then
      printf '%s\n' "$skills_dir"
      return 0
    fi
  fi
  return 1
}

if is_url "$file"; then
  echo "action: fetch url -> local file" >&2
  file="$(fetch_if_url "$file")"
  echo "fetched: $file" >&2
fi

if [ ! -f "$file" ]; then
  need "file not found: $file"
fi

echo "## preflight" >&2
ls -la "$file" 2>/dev/null >&2 || true
if command -v wc >/dev/null 2>&1; then
  bytes="$(wc -c <"$file" 2>/dev/null | tr -d ' ' || true)"
  [ -n "${bytes:-}" ] && echo "bytes=$bytes" >&2
fi
if command -v file >/dev/null 2>&1; then
  file "$file" 2>/dev/null >&2 || true
fi

base="$(basename "$file" 2>/dev/null || echo runfile)"
log="/tmp/${base}.log.$(ts)"

prefer_dotrun=0
case "$run_via_dotrun" in
  yes) prefer_dotrun=1 ;;
  no) prefer_dotrun=0 ;;
  auto)
    if have is-opkg; then
      prefer_dotrun=1
    fi
    ;;
  *)
    prefer_dotrun=0
    ;;
esac

if [ "$prefer_dotrun" -eq 1 ] && [ $# -eq 0 ]; then
  tmpdir="/tmp/is-root/tmp"
  mkdir -p "$tmpdir" 2>/dev/null || true
  tmp="$tmpdir/$base.dotrun.$(ts)"
  echo "action: install via is-opkg dotrun (will record pkg diff; args not supported)" >&2
  echo "note: using a temp copy to avoid dotrun removing user's original file" >&2
  cp -f "$file" "$tmp"
  cd "$(dirname "$tmp")" 2>/dev/null || true
  if have tee; then
    run_logged is-opkg dotrun "$tmp"
  else
    is-opkg dotrun "$tmp"
    echo "log: skipped (tee not found)" >&2
  fi
else
  echo "action: chmod 755 $file" >&2
  chmod 755 "$file" 2>/dev/null || chmod +x "$file"

  exec_path="$file"
  case "$exec_path" in
    */*) : ;;
    *) exec_path="./$exec_path" ;;
  esac

  echo "action: execute $exec_path $*" >&2
  if have tee; then
    run_logged "$exec_path" "$@"
  else
    "$exec_path" "$@"
    echo "log: skipped (tee not found)" >&2
  fi
fi
