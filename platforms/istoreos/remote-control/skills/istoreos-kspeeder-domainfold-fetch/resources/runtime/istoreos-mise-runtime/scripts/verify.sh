#!/bin/sh
set -eu
runtime="${1:?runtime is required}"
version="${2:?resolved version is required}"
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
if [ "${ISTORE_RUNTIME_ENTERED:-}" != 1 ]; then exec sh "$here/exec.sh" "$here/verify.sh" "$@"; fi
. "$here/environment.sh"
runtime_environment_check
spec="$runtime@$version"
export MISE_AUTO_INSTALL=0 MISE_NOT_FOUND_AUTO_INSTALL=0
installed_dir="$(mise where "$spec")"
[ -n "$installed_dir" ] && [ -d "$installed_dir" ] || { echo 'failed: runtime-not-installed' >&2; exit 4; }
case "$runtime" in
  python)
    ks-cli mise exec "$spec" -- python -c 'import sys, pathlib, ssl, sqlite3, bz2, lzma, ctypes, venv; root=pathlib.Path(sys.argv[1]).resolve(); exe=pathlib.Path(sys.executable).resolve(); assert root in exe.parents, (exe, root); assert sys.version.split()[0] == sys.argv[2], sys.version; print("python_executable="+str(exe)); print("python_version="+sys.version.split()[0]); print("runtime_modules=ok")' "$installed_dir" "$version"
    ks-cli mise exec "$spec" -- python -m pip --version
    ;;
  node)
    ks-cli mise exec "$spec" -- node -e 'const fs=require("node:fs"),p=require("node:path");const root=fs.realpathSync(process.argv[1]),exe=fs.realpathSync(process.execPath);if(!exe.startsWith(root+p.sep)||process.versions.node!==process.argv[2])process.exit(4);console.log("node_executable="+exe);console.log("node_version="+process.versions.node)' "$installed_dir" "$version"
    ks-cli mise exec "$spec" -- npm --version
    ;;
  go)
    goroot="$(ks-cli mise exec "$spec" -- go env GOROOT)"
    [ "$(CDPATH= cd -- "$goroot" && pwd -P)" = "$(CDPATH= cd -- "$installed_dir" && pwd -P)" ] || { echo 'failed: Go SDK source does not match mise installation' >&2; exit 4; }
    go_version="$(ks-cli mise exec "$spec" -- go version)"
    case "$go_version" in "go version go$version "*) ;; *) echo "failed: version-mismatch: $go_version (expected $version)" >&2; exit 4 ;; esac
    printf '%s\n' "$go_version"
    printf 'go_sdk=%s\n' "$goroot"
    ;;
  *) echo 'failed: unsupported runtime' >&2; exit 2 ;;
esac
