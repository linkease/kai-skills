#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
collect="$root/skills/istoreos-source-introspect/scripts/collect.sh"
ensure="$root/skills/istoreos-service-manager/scripts/ensure.sh"
detect="$root/skills/istoreos-storage-path/scripts/detect.sh"
probe="$root/skills/istoreos-storage-path/scripts/probe.sh"
ensure_kspeeder="$root/skills/istoreos-kspeeder-domainfold-fetch/scripts/ensure_running.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
rootfs="$tmp/rootfs"
mkdir -p "$rootfs/etc/init.d" "$rootfs/etc/config" "$rootfs/rom/etc/init.d" "$rootfs/usr/lib/lua/luci"

if ISTOREOS_ROOT="$rootfs" sh "$collect" '../shadow' >"$tmp/out" 2>"$tmp/err"; then
  echo 'failed: source introspection accepted a traversal name' >&2
  exit 1
fi
jq -e '.operationStatus=="failed" and .errors[0].code=="INVALID_ARGUMENT"' "$tmp/out" >/dev/null

printf '%s\n' '#!/bin/sh' 'TOKEN=source-secret' 'endpoint="https://alice:secret@example.invalid/api"' >"$rootfs/etc/init.d/demo"
out="$(ISTOREOS_ROOT="$rootfs" sh "$collect" demo 2>/dev/null)"
if printf '%s\n' "$out" | grep -qE 'source-secret|alice:secret'; then
  echo 'failed: source introspection leaked a credential' >&2
  exit 1
fi
printf '%s\n' "$out" | grep -Fq '[REDACTED]'

printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "$1" >>"${SERVICE_MARKER:?}"' >"$rootfs/etc/init.d/demo"
chmod +x "$rootfs/etc/init.d/demo"
if ISTOREOS_ROOT="$rootfs" SERVICE_MARKER="$tmp/service.marker" bash "$ensure" demo >"$tmp/out" 2>"$tmp/err"; then
  echo 'failed: service mutation ran without confirmation' >&2
  exit 1
fi
[ ! -e "$tmp/service.marker" ]
jq -e '.operationStatus=="failed" and .errors[0].code=="INVALID_ARGUMENT"' "$tmp/out" >/dev/null
# Full explicit request/precondition/authorization and failure-path coverage lives
# in test_writes.py; these legacy aliases must reject implicit service workflows.
if KAIPLUS_CONFIRMED=1 ISTOREOS_ROOT="$rootfs" bash "$ensure" '../demo' >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
[ ! -e "$tmp/service.marker" ]
if ISTOREOS_ROOT="$rootfs" bash "$ensure_kspeeder" >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
[ ! -e "$tmp/service.marker" ]
jq -e '.operationStatus=="failed"' "$tmp/out" >/dev/null

missing="$tmp/not-created/by-detect"
observation_code=0
KAIPLUS_HOME="$missing" sh "$detect" >"$tmp/out" 2>"$tmp/err" || observation_code=$?
[ "$observation_code" -eq 0 ] || [ "$observation_code" -eq 1 ]
jq -e '.operation=="system.observe" and .readOnly==true and (has("chosen")|not)' "$tmp/out" >/dev/null
[ ! -e "$missing" ]

if sh "$probe" "$missing" >"$tmp/out" 2>"$tmp/err"; then
  echo 'failed: writable-path probe ran without confirmation' >&2
  exit 1
fi
[ ! -e "$missing" ]
grep -q 'KAIPLUS_CONFIRMED=1' "$tmp/err"

if KAIPLUS_CONFIRMED=1 sh "$probe" "$missing" >/dev/null 2>&1; then exit 1; fi
[ ! -e "$missing" ]
mkdir -p "$missing"
KAIPLUS_CONFIRMED=1 sh "$probe" "$missing" >/dev/null
[ -z "$(ls -A "$missing")" ]

echo 'ok: safety boundaries reject unsafe names, redact secrets, and gate writes'
