#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"

need_file() {
  [ -f "$root/$1" ] || {
    echo "failed: missing $1" >&2
    exit 1
  }
}

common="$root/../common"
[ -d "$common/skills" ] || common="$root/../../system-packs/common"
[ -d "$common/skills" ] || common="$root"
need_skill() {
  if [ -f "$common/skills/$1/SKILL.md" ]; then return; fi
  need_file "skills/$1/SKILL.md"
}

need_file "manifest.json"
need_file "home-prompts.json"
need_file "agents/system.md"
need_file "agents/istoreos.md"
need_file "TASK_ROUTING.md"
need_file "tests/test_download_acceleration_dispatch.sh"
need_file "tests/test_system_helpers.sh"
need_file "tests/test_network_quality_helpers.sh"
need_file "tests/test_skill_architecture.sh"
need_file "tests/test_app_diagnostics_contract.sh"
need_file "tests/test_app_diagnostics_collector.sh"
need_file "tests/test_app_diagnostics_classifier.sh"
need_file "tests/test_app_diagnostics_catalog.sh"
need_file "tests/test_app_diagnostics_inspect.sh"
need_file "tests/test_store_catalog_search.sh"
need_file "tests/test_safety_boundaries.sh"
need_file "tests/test_unknown_observer.sh"

need_skill "kai-project-dependencies"
need_skill "kai-tool-bootstrap"
need_skill "istoreos-system-task-router"
need_skill "kai-download-acceleration"
need_skill "istoreos-docker-acceleration-istoreenhance"
need_skill "istoreos-kspeeder-domainfold-fetch"
need_skill "istoreos-docker-basics"
need_skill "kai-software"
need_skill "kai-storage-files"
need_skill "istoreos-service-manager"
need_skill "istoreos-logs-and-diagnostics"
need_skill "istoreos-backup-restore"
need_skill "istoreos-luci-recovery"
need_skill "istoreos-systools"
need_skill "kai-dev-environment"
need_skill "istoreos-network-quality"
need_skill "istoreos-app-diagnostics"

grep -F 'istoreos-network-quality' "$root/TASK_ROUTING.md" >/dev/null
grep -F 'istoreos-network-quality' "$root/skills/istoreos-system-task-router/SKILL.md" >/dev/null

for script in "$root"/skills/*/scripts/*.sh; do
  [ -f "$script" ] || continue
  sh -n "$script"
done

sh "$root/tests/test_download_acceleration_dispatch.sh"
sh "$root/tests/test_system_helpers.sh"
sh "$root/tests/test_package_runtime_environment.sh"
sh "$root/tests/test_legacy_package_queries.sh"
sh "$root/tests/test_runtime_install.sh"
sh "$root/tests/test_runtime_results.sh"
sh "$root/tests/test_runtime_diagnosis.sh"
sh "$root/tests/test_dependency_commands.sh"
sh "$root/tests/test_dependency_gateway_evidence.sh"
sh "$root/tests/test_dependency_smoke_contract.sh"
sh "$root/tests/test_network_quality_helpers.sh"
sh "$root/tests/test_skill_architecture.sh"
sh "$root/tests/test_app_diagnostics_contract.sh"
sh "$root/tests/test_app_diagnostics_collector.sh"
sh "$root/tests/test_app_diagnostics_classifier.sh"
sh "$root/tests/test_app_diagnostics_catalog.sh"
sh "$root/tests/test_app_diagnostics_inspect.sh"
sh "$root/tests/test_store_catalog_search.sh"
sh "$root/tests/test_safety_boundaries.sh"
sh "$root/tests/test_unknown_observer.sh"

echo "ok: istoreos profile smoke passed"
