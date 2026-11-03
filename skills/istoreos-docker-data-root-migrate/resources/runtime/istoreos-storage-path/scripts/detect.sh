#!/bin/sh
set -eu

say() { echo "$*" >&2; }

candidate_ok() {
  base="$1"
  [ -n "$base" ] || return 1
  [ -d "$base" ] && [ -w "$base" ]
}

chosen=""
best_avail=0

cands="$(df -P -k 2>/dev/null | awk '
  NR==1 { next }
  $6 ~ "^/mnt/" || $6 ~ "^/media/" || $6 ~ "^/opt/" { print $6 "\t" $4 }
')"

tab="$(printf '\t')"
while IFS="$tab" read -r mp avail; do
  [ -n "${mp:-}" ] || continue
  [ -n "${avail:-}" ] || continue
  [ "$avail" -ge 1048576 ] 2>/dev/null || continue
  candidate_ok "$mp" || continue
  if [ "$avail" -gt "$best_avail" ] 2>/dev/null; then
    best_avail="$avail"
    chosen="$mp"
  fi
done <<EOF
$cands
EOF

if [ -n "$chosen" ]; then
  say "picked: base path=$chosen (largest writable mount under /mnt|/media|/opt, >= 1GiB free)"
  echo "$chosen"
  exit 0
fi

base_from_kaiplus_home() {
  home="${KAIPLUS_HOME:-}"
  [ -n "$home" ] || return 1
  case "$home" in
    */Configs/*) printf '%s\n' "${home%%/Configs/*}" ;;
    */Configs) printf '%s\n' "${home%/Configs}" ;;
    *) printf '%s\n' "$home" ;;
  esac
}

fallback="$(base_from_kaiplus_home || true)"
if [ -n "$fallback" ] && candidate_ok "$fallback"; then
  say "picked: base path=$fallback (derived from KAIPLUS_HOME)"
  echo "$fallback"
  exit 0
fi

say "failed: cannot auto-pick an existing writable base path; choose a mounted data path or set KAIPLUS_HOME on external storage. Use probe.sh only after confirmation when a real write test is required."
exit 1
