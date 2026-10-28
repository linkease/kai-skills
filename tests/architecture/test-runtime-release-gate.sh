#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cp -R "$root/components/system-packs/istoreos" "$tmp/pack"
cp -R "$root/components/system-packs/common" "$tmp/common"
for test in test_package_runtime_environment.sh test_runtime_results.sh; do
  printf '%s\n' '#!/bin/sh' 'echo injected-runtime-contract-failure >&2' 'exit 1' >"$tmp/pack/tests/$test"
  if sh "$tmp/pack/drills/profile-smoke.sh" >"$tmp/out" 2>&1; then
    echo "failed: profile gate skipped failing $test" >&2
    exit 1
  fi
  grep -F injected-runtime-contract-failure "$tmp/out"
  cp "$root/components/system-packs/istoreos/tests/$test" "$tmp/pack/tests/$test"
done
echo 'ok: release/profile gate includes the runtime regression tests'
