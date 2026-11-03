#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
repo_root="$(CDPATH= cd -- "$root/.." && pwd -P)"

need_file() {
  [ -f "$root/$1" ] || {
    echo "failed: missing $1" >&2
    exit 1
  }
}

need_file "manifest.json"
need_file "home-prompts.json"
need_file "agents/remote-istoreos.md"
need_file "TASK_ROUTING.md"
[ -f "$repo_root/istoreos/skills/istoreos-docker-acceleration-istoreenhance/SKILL.md" ] || {
  echo "failed: missing canonical iStoreOS system pack" >&2
  exit 1
}

[ -f "$repo_root/components/transports/ssh/skills/target-ssh-controller/SKILL.md" ] || {
  echo "failed: missing canonical SSH transport" >&2
  exit 1
}
[ -f "$repo_root/components/transports/luci-http/skills/luci-http-controller/SKILL.md" ] || {
  echo "failed: missing canonical LuCI HTTP transport" >&2
  exit 1
}

if find "$root" -mindepth 2 -maxdepth 2 -name SKILL.md | grep . >/dev/null 2>&1; then
  echo "failed: remote preset contains manually maintained skills" >&2
  exit 1
fi

for script in "$repo_root"/components/transports/*/skills/*/scripts/*.sh; do
  [ -f "$script" ] || continue
  sh -n "$script"
done

tmp="$(mktemp -d "${TMPDIR:-/tmp}/linkease-remote-smoke.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
sh "$root/install.sh" --target "$tmp" --copy >/dev/null
[ "$(find "$tmp" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l | tr -d ' ')" -eq 24 ] || {
  echo "failed: remote preset did not install 22 system + 2 transport skills" >&2
  exit 1
}
diff -ru "$repo_root/skills/kai-software" "$tmp/kai-software" >/dev/null || {
  echo 'failed: installed public skill differs from its independent package' >&2
  exit 1
}

echo "ok: remote-control-istoreos profile smoke passed"
