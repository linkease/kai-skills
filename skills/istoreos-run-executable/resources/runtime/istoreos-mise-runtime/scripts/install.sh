#!/bin/sh
set -eu
runtime="${1:-}"
version="${2:-}"
activation="${3:-none}"
[ "${KAIPLUS_CONFIRMED:-}" = 1 ] || { echo 'blocked: explicit user authorization is required' >&2; exit 3; }
case "$runtime" in python|node|go) ;; nodejs) runtime=node ;; golang) runtime=go ;; *) echo 'failed: supported runtimes are python, node and go' >&2; exit 2 ;; esac
case "$version" in ''|-*|*[!A-Za-z0-9._-]*) echo 'failed: invalid or missing version' >&2; exit 2 ;; esac
case "$activation" in none|project|global) ;; *) echo 'failed: activation must be none, project or global' >&2; exit 2 ;; esac
if [ "$runtime" = python ] && ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo 'failed: explicit-python-version: verify a complete version before install; latest/partial selection is version-dependent' >&2
  exit 4
fi
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
if [ "${ISTORE_RUNTIME_ENTERED:-}" != 1 ]; then exec sh "$here/exec.sh" "$here/install.sh" "$runtime" "$version" "$activation"; fi
. "$here/result.sh"
install_phase=environment
environment_validation=failed
install_log=""
install_result() {
  code=$?
  trap - EXIT HUP INT TERM
  [ -z "$install_log" ] || rm -f "$install_log"
  status=failed; validation=not-run
  [ "$install_phase" != verification ] || validation=failed
  if [ "$code" = 0 ]; then status=passed; validation=passed; fi
  result_emit "$status" runtime-install "$code" runtime "$runtime" version "$version" activation "$activation" \
    phase "$install_phase" environment_validation "$environment_validation" runtime_validation "$validation" gateway_validation not-applicable
  exit "$code"
}
trap install_result EXIT
. "$here/environment.sh"
runtime_environment_check
environment_validation=passed
configured_home="$(uci -q get mise.main.runtime_dir)"
[ "$HOME" = "$configured_home" ] || { echo 'failed: wrong runtime HOME; enter mise-exec' >&2; exit 4; }
case "$PATH" in "$HOME/.local/share/mise/shims:"*) ;; *) echo 'failed: missing integrated shims' >&2; exit 4 ;; esac
command -v mise >/dev/null 2>&1 && command -v ks-cli >/dev/null 2>&1 || { echo 'failed: mise or ks-cli is missing; use the system-integrated package path' >&2; exit 4; }
# There is no global skip_checksum setting in the inspected mise contract.
# Go owns its SDK checksum switch; Node owns verify; Python core verifies artifacts.
if [ "$runtime" = go ] && [ "$(ks-cli mise settings get go.skip_checksum)" != false ]; then
  echo 'failed: integrity-disabled: Go SDK checksum verification must remain enabled' >&2
  exit 4
fi
global_gpg="$(ks-cli mise settings get gpg_verify 2>/dev/null || true)"
[ "$global_gpg" != false ] || { echo 'failed: integrity-disabled: global signature verification was disabled' >&2; exit 4; }
if [ "$runtime" = python ]; then
  arch="$(uname -m)"
  case "$arch" in x86_64|aarch64) ;; *) echo "failed: unsupported-architecture: no verified precompiled mapping for $arch" >&2; exit 4 ;; esac
  libc=unknown
  for loader in "${ISTORE_SYSTEM_ROOT:-}"/lib/ld-musl-*.so*; do [ ! -e "$loader" ] || libc=musl; done
  if [ "$libc" = unknown ] && command -v getconf >/dev/null 2>&1 && getconf GNU_LIBC_VERSION >/dev/null 2>&1; then libc=glibc; fi
  case "$libc" in musl) precompiled_os=unknown-linux-musl ;; glibc) precompiled_os=unknown-linux-gnu ;; *) echo 'failed: unknown-libc: inspect the target loader before choosing a Python archive' >&2; exit 4 ;; esac
  export MISE_PYTHON_COMPILE=0 MISE_PYTHON_PRECOMPILED_ARCH="$arch" MISE_PYTHON_PRECOMPILED_OS="$precompiled_os"
fi
if [ "$runtime" = node ]; then
  # Preserve integration HOME/PATH; replace only obsolete Node process settings.
  unset MISE_NODE_MIRROR_URL
  export MISE_NODE_VERIFY=1
  mirror="$(ks-cli mise settings get node.mirror_url 2>/dev/null || true)"
  [ -z "$mirror" ] || { echo 'failed: custom-node-mirror: inspect persisted configuration before using platform routing' >&2; exit 4; }
  [ "$(ks-cli mise settings get node.verify)" = true ] || { echo 'failed: node integrity verification is disabled' >&2; exit 4; }
  gpg="$(ks-cli mise settings get node.gpg_verify 2>/dev/null || true)"
  [ "$gpg" != false ] || { echo 'failed: integrity-disabled: Node signature verification was disabled' >&2; exit 4; }
fi
ks-cli doctor mise --json
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  resolved="$(ks-cli mise latest "$runtime@$version")"
  printf '%s\n' "$resolved" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo 'failed: version-selection: resolver did not return one complete stable version' >&2; exit 4; }
  case "$version" in
    [0-9]*) case "$resolved" in "$version".*) ;; *) echo 'failed: version-selection: resolved version does not match the requested numeric prefix' >&2; exit 4 ;; esac ;;
  esac
  printf 'resolved_version=%s (requested %s)\n' "$resolved" "$version"
  version="$resolved"
fi
spec="$runtime@$version"
install_phase=installation
log="$(mktemp "${TMPDIR:-/tmp}/istore-install.XXXXXX")"
install_log="$log"
status=0
ks-cli mise install "$spec" >"$log" 2>&1 || status=$?
cat "$log"
if [ "$status" != 0 ]; then
  sh "$here/diagnose.sh" "$log" >&2
  exit "$status"
fi
case "$activation" in
  project) ks-cli mise use "$spec" ;;
  global) ks-cli mise use --global "$spec" ;;
esac
install_phase=verification
sh "$here/verify.sh" "$runtime" "$version"
printf 'installed=%s activation=%s\n' "$spec" "$activation"
