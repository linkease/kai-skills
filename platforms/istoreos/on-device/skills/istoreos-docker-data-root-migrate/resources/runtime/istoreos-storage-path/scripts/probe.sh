#!/bin/sh
set -eu

base="${1:-}"

need() {
  echo "need-confirmation: $*" >&2
  exit 2
}

[ -n "$base" ] || { echo "usage: $0 <absolute-base-path>" >&2; exit 2; }
case "$base" in
  /*) ;;
  *) echo "invalid path: an absolute base path is required" >&2; exit 2 ;;
esac
[ "${KAIPLUS_CONFIRMED:-}" = "1" ] || need "this creates the selected directory when missing and writes a temporary probe file; rerun with KAIPLUS_CONFIRMED=1 after user confirmation"

mkdir -p "$base" 2>/dev/null || { echo "failed: cannot create base path: $base" >&2; exit 1; }
probe="$base/.istore_write_test.$$"
trap 'rm -f "$probe" 2>/dev/null || true' EXIT HUP INT TERM
: >"$probe" 2>/dev/null || { echo "failed: base path is not writable: $base" >&2; exit 1; }
rm -f "$probe" 2>/dev/null || { echo "failed: cannot remove probe file: $probe" >&2; exit 1; }
trap - EXIT HUP INT TERM
echo "ok: writable base path=$base"
