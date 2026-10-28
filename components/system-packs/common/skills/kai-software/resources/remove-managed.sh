#!/bin/sh
set -eu
# Shared Linux installer policy. Native facts come only from canonical Rust
# zsetup; this file does not download, execute metadata or install packages.

installer_storage_error() { printf 'Installer storage: %s\n' "$*" >&2; }

installer_valid_directory() {
    case "$1" in
        /*) ;;
        *) installer_storage_error 'directory must be absolute'; return 2 ;;
    esac
    case "$1" in
        /|*/../*|*/..|*/./*|*/.|*//*|*'
'*|*'	'*) installer_storage_error 'directory must be a normalized non-root path'; return 2 ;;
    esac
}

# Pure layout; no directory is created and no permission is inferred from UID.
# The business adapter must separately validate that the requested scope works.
installer_layout() {
    is_app=$1
    case "$is_app" in ''|*[!a-z0-9_-]*) return 2 ;; esac
    INSTALLER_SCOPE=${installer_scope:-$2}
    case "$INSTALLER_SCOPE" in user|system) ;; *) installer_storage_error 'scope must be user or system'; return 2 ;; esac
    if [ "$INSTALLER_SCOPE" = user ]; then
        : "${HOME:?HOME is required for user installation}"
        installer_valid_directory "$HOME" || return $?
        INSTALLER_PREFIX=${installer_prefix:-$HOME/.local/lib/linkease/$is_app}
        INSTALLER_COMMAND="$HOME/.local/bin/$is_app"
    else
        INSTALLER_PREFIX=${installer_prefix:-/opt/linkease/$is_app}
        INSTALLER_COMMAND="$INSTALLER_PREFIX/current/bin/$is_app"
    fi
    INSTALLER_PREFIX=${INSTALLER_PREFIX%/}
    installer_valid_directory "$INSTALLER_PREFIX"
}

# Extra simultaneously needed bytes: download + expanded files + commit copies
# + backup copies. An existing version already occupies disk; count it again
# only if this transaction creates an additional copy. Unknown sizes are errors.
# Keep arithmetic within signed 32-bit POSIX shell range, including the margin.
installer_space_budget() {
    [ "$#" = 4 ] || return 2
    is_sum=0
    for is_size in "$@"; do
        case "$is_size" in ''|*[!0-9]*) installer_storage_error 'artifact size budget is unknown or invalid'; return 2 ;; esac
        [ "${#is_size}" -le 10 ] && [ "$is_size" -le 1900000000 ] || return 2
        # Reject leading zeroes so shell arithmetic cannot interpret octal.
        case "$is_size" in 0) ;; 0*) return 2 ;; esac
        is_sum=$((is_sum + is_size))
        [ "$is_sum" -le 1900000000 ] || return 2
    done
    INSTALLER_REQUIRED_BYTES=$((is_sum + (is_sum + 9) / 10 + 8388608))
}

# Check at planning and again under the installation lock before activation.
# Arguments: path, peak-extra byte budget, executes-files(0/1), needs-write(0/1).
# Explicit target paths do not silently authorize tmpfs or unknown backing.
installer_storage_check() {
    is_path=$1; is_needed=$2; is_exec=$3; is_write=$4
    case "$is_needed" in ''|*[!0-9]*) return 2 ;; esac
    [ "${#is_needed}" -le 10 ] && [ "$is_needed" -le 2147483647 ] || return 2
    case "$is_exec:$is_write" in 0:0|0:1|1:0|1:1) ;; *) return 2 ;; esac
    is_memory=$("$ZSETUP_BIN" storage "$is_path" get memory_backed) || {
        installer_storage_error 'storage probe unavailable; a Rust zsetup with storage support is required'; return 12;
    }
    case "$is_memory" in
        false) ;;
        true) installer_storage_error "memory filesystem at $is_path; choose a persistent directory"; return 12 ;;
        *) installer_storage_error "cannot establish persistent backing at $is_path; choose a verified directory"; return 12 ;;
    esac
    is_readonly=$("$ZSETUP_BIN" storage "$is_path" get read_only) || return 12
    [ "$is_readonly" = false ] || { installer_storage_error "read-only or unknown mount at $is_path"; return 12; }
    if [ "$is_exec" = 1 ]; then
        is_noexec=$("$ZSETUP_BIN" storage "$is_path" get noexec) || return 12
        [ "$is_noexec" = false ] || { installer_storage_error "execution is unavailable at $is_path"; return 12; }
    fi
    if [ "$is_write" = 1 ]; then
        is_writable=$("$ZSETUP_BIN" storage "$is_path" get writable) || return 12
        [ "$is_writable" = true ] || { installer_storage_error "write permission is required at $is_path"; return 12; }
    fi
    is_available=$("$ZSETUP_BIN" storage "$is_path" get available_bytes) || return 12
    case "$is_available" in ''|*[!0-9]*) return 12 ;; esac
    [ "$is_available" -ge "$is_needed" ] || {
        installer_storage_error "insufficient space at $is_path: need $is_needed bytes, available $is_available; choose another directory"; return 12;
    }
    is_inodes=$("$ZSETUP_BIN" storage "$is_path" get available_inodes) || return 12
    case "$is_inodes" in
        unknown) installer_storage_error "inode availability is unknown at $is_path" ;;
        ''|*[!0-9]*) return 12 ;;
        *) [ "$is_inodes" -gt 0 ] || { installer_storage_error "no free inodes at $is_path"; return 12; } ;;
    esac
}

# Directory selection never creates files. In unattended mode a failed check
# is terminal; only an actual foreground terminal may supply another location.
installer_storage_select() {
    INSTALLER_STORAGE_PATH=$1
    is_select_needed=$2; is_select_exec=$3; is_select_write=$4
    while :; do
        if installer_storage_check "$INSTALLER_STORAGE_PATH" "$is_select_needed" "$is_select_exec" "$is_select_write"; then
            return 0
        fi
        [ -t 0 ] || return 12
        printf 'Enter another persistent absolute directory (empty cancels): ' >&2
        IFS= read -r INSTALLER_STORAGE_PATH || return 12
        [ -n "$INSTALLER_STORAGE_PATH" ] || return 12
        installer_valid_directory "$INSTALLER_STORAGE_PATH" || return 2
    done
}

# A single peak budget covers both locations when they share a filesystem;
# checking the same budget on each path does not sum it twice. No files created.
installer_preflight() {
    installer_layout "$1" "$2" || return $?
    installer_storage_select "$INSTALLER_PREFIX" "$3" 1 "$4" || return $?
    INSTALLER_PREFIX=$INSTALLER_STORAGE_PATH
    INSTALLER_WORK_ROOT=${installer_work_dir:-${ZSETUP_WORK_DIR:-$INSTALLER_PREFIX/.staging}}
    installer_valid_directory "$INSTALLER_WORK_ROOT" || return $?
    installer_storage_select "$INSTALLER_WORK_ROOT" "$3" 1 "$4" || return $?
    INSTALLER_WORK_ROOT=$INSTALLER_STORAGE_PATH
    printf 'Install plan: application=%s scope=%s prefix=%s staging=%s peak-extra-bytes=%s\n' \
        "$1" "$INSTALLER_SCOPE" "$INSTALLER_PREFIX" "$INSTALLER_WORK_ROOT" "$3" >&2
}

# One shell coordinator owns the lease, transaction, native child and cleanup.
# Native download/capture own their task/connection/process trees. Do not wrap
# them in another run owner that could SIGKILL a coordinator before its join.
installer_transaction_begin() {
    umask 077
    INSTALLER_CHILD=
    INSTALLER_SPAWNING=0
    INSTALLER_SIGNAL=0
    INSTALLER_LOCK_HELD=0
    INSTALLER_TRANSACTION_ACTIVE=0
    transaction_dir=
    [ ! -L "$INSTALLER_WORK_ROOT" ] || return 12
    mkdir -p "$INSTALLER_WORK_ROOT" || return 12
    [ "$("$ZSETUP_BIN" storage "$INSTALLER_WORK_ROOT" get private_directory)" = true ] || {
        printf 'Installer: staging must be a private directory owned by the current user: %s\n' "$INSTALLER_WORK_ROOT" >&2
        return 12
    }
    INSTALLER_LOCK="$INSTALLER_WORK_ROOT/.install-lock"
    if ! mkdir "$INSTALLER_LOCK" 2>/dev/null; then
        printf 'Installer: active or interrupted transaction at %s; inspect/recover it before retrying.\n' "$INSTALLER_LOCK" >&2
        return 2
    fi
    INSTALLER_LOCK_HELD=1
    trap 'installer_transaction_exit $?' EXIT
    trap 'installer_transaction_signal 129' HUP
    trap 'installer_transaction_signal 130' INT
    trap 'installer_transaction_signal 143' TERM
    printf '%s\n' "$$" > "$INSTALLER_LOCK/owner"
    transaction_dir=$(mktemp -d "$INSTALLER_WORK_ROOT/.transaction.XXXXXX") || return 12
    printf '%s\n' "$$" > "$transaction_dir/.owner"
    INSTALLER_TRANSACTION_ACTIVE=1
}

installer_transaction_signal() {
    INSTALLER_SIGNAL=$1
    # During spawn, record the signal until the PID has been adopted. All other
    # phases exit through the single cleanup coordinator immediately.
    [ "$INSTALLER_SPAWNING" = 1 ] || exit "$INSTALLER_SIGNAL"
}

installer_owned_native() {
    [ "$1" = "$ZSETUP_BIN" ] || return 2
    [ "$INSTALLER_SIGNAL" = 0 ] || return "$INSTALLER_SIGNAL"
    INSTALLER_SPAWNING=1
    if [ "${INSTALLER_BRIDGE_OPEN:-0}" = 1 ]; then
        "$@" <&0 3>&- 4>&- &
    else
        "$@" <&0 &
    fi
    INSTALLER_CHILD=$!
    INSTALLER_SPAWNING=0
    [ "$INSTALLER_SIGNAL" = 0 ] || exit "$INSTALLER_SIGNAL"
    it_status=0
    wait "$INSTALLER_CHILD" || it_status=$?
    INSTALLER_CHILD=
    return "$it_status"
}

installer_transaction_cleanup() {
    if [ -n "$INSTALLER_CHILD" ]; then
        kill -TERM "$INSTALLER_CHILD" 2>/dev/null || true
        wait "$INSTALLER_CHILD" 2>/dev/null || true
        INSTALLER_CHILD=
    fi
    # Business rollback runs only after all native operations have joined.
    if [ -n "${INSTALLER_CLEANUP_HOOK:-}" ]; then
        # The original signal exit is retained by transaction_exit. Recovery
        # itself must be allowed to run joined native operations after cancel.
        INSTALLER_SIGNAL=0
        "$INSTALLER_CLEANUP_HOOK" || {
            printf 'Installer: recovery incomplete; staging and lease retained at %s\n' "$INSTALLER_WORK_ROOT" >&2
            return 12
        }
    fi
    if [ -n "$transaction_dir" ]; then
        case "$transaction_dir" in "$INSTALLER_WORK_ROOT"/.transaction.*) ;; *) return 12 ;; esac
        [ ! -L "$transaction_dir" ] && [ ! -L "$transaction_dir/.owner" ] && [ -f "$transaction_dir/.owner" ] || return 12
        set -- $(wc -c < "$transaction_dir/.owner")
        [ "$1" -le 16 ] || return 12
        it_owner=
        IFS= read -r it_owner < "$transaction_dir/.owner" || return 12
        [ "$it_owner" = "$$" ] || return 12
        rm -rf "$transaction_dir" || return 12
        transaction_dir=
    fi
    if [ "$INSTALLER_LOCK_HELD" = 1 ]; then
        rm -f "$INSTALLER_LOCK/owner" || return 12
        rmdir "$INSTALLER_LOCK" || return 12
        INSTALLER_LOCK_HELD=0
    fi
    INSTALLER_TRANSACTION_ACTIVE=0
}

installer_transaction_exit() {
    it_exit=$1
    INSTALLER_EXIT_CODE=$it_exit
    trap - EXIT
    trap '' HUP INT TERM
    installer_transaction_cleanup || { [ "$it_exit" != 0 ] || it_exit=12; }
    exit "$it_exit"
}

installer_transaction_finish() {
    INSTALLER_EXIT_CODE=0
    installer_transaction_cleanup || return $?
    trap - EXIT HUP INT TERM
}

# Owner implementation for user-scoped binary clients. No service operations.
remove_conflict() { printf 'Managed removal conflict: %s\n' "$*" >&2; exit 11; }
remove_plain_path() {
    installer_valid_directory "$1" || exit 2
    rp_path=$1
    while [ "$rp_path" != / ]; do
        [ ! -L "$rp_path" ] || remove_conflict 'symbolic link in directory path'
        rp_path=${rp_path%/*}; [ -n "$rp_path" ] || rp_path=/
    done
}
remove_main() {
    [ "$#" = 1 ] || exit 2
    app=$1
    case "$app" in linkspace|ks-cli|kspeeder) ;; *) exit 2 ;; esac
    : "${ZSETUP_BIN:?an existing canonical zsetup is required}"
    installer_scope=user
    installer_prefix=${ZSETUP_INSTALL_PREFIX:-}
    installer_layout "$app" user || exit $?
    remove_plain_path "$INSTALLER_PREFIX"
    remove_plain_path "${INSTALLER_COMMAND%/*}"
    # A completed removal is idempotent; foreign remnants are never deleted.
    if [ ! -e "$INSTALLER_PREFIX/.managed" ] && [ ! -L "$INSTALLER_PREFIX/.managed" ]; then
        for path in "$INSTALLER_PREFIX/versions" "$INSTALLER_PREFIX/current" "$INSTALLER_PREFIX/previous" "$INSTALLER_COMMAND"; do
            { [ ! -e "$path" ] && [ ! -L "$path" ]; } || remove_conflict 'installation has no ownership marker'
        done
        return 0
    fi
    [ -f "$INSTALLER_PREFIX/.managed" ] && [ ! -L "$INSTALLER_PREFIX/.managed" ] || remove_conflict 'invalid ownership marker'
    [ "$(wc -c < "$INSTALLER_PREFIX/.managed")" -le 65 ] || remove_conflict 'oversized ownership marker'
    [ "$(cat "$INSTALLER_PREFIX/.managed")" = "$app" ] || remove_conflict 'different application owner'
    [ "$("$ZSETUP_BIN" storage "$INSTALLER_PREFIX" get private_directory)" = true ] || remove_conflict 'prefix is not private and owned'
    INSTALLER_WORK_ROOT=${ZSETUP_WORK_DIR:-$INSTALLER_PREFIX/.staging}
    remove_plain_path "$INSTALLER_WORK_ROOT"
    installer_transaction_begin || exit $?
    command -v sha256sum >/dev/null 2>&1 || { printf 'Managed removal requires sha256sum for local integrity verification.\n' >&2; exit 127; }
    [ -d "$INSTALLER_PREFIX/versions" ] && [ ! -L "$INSTALLER_PREFIX/versions" ] || remove_conflict 'invalid versions directory'
    for version_dir in "$INSTALLER_PREFIX"/versions/* "$INSTALLER_PREFIX"/versions/.[!.]* "$INSTALLER_PREFIX"/versions/..?*; do
        [ -e "$version_dir" ] || [ -L "$version_dir" ] || continue
        version=${version_dir##*/}
        case "$version" in ''|.*|*[!a-zA-Z0-9._+-]*) remove_conflict 'invalid version identifier' ;; esac
        [ -d "$version_dir" ] && [ ! -L "$version_dir" ] && [ -d "$version_dir/bin" ] && [ ! -L "$version_dir/bin" ] || remove_conflict 'invalid version directory'
        binary="$version_dir/bin/$app"; marker="$binary.verified"
        for path in "$binary" "$marker"; do
            [ -f "$path" ] && [ ! -L "$path" ] || remove_conflict 'unverified program or marker'
        done
        [ "$(wc -c < "$marker")" -le 128 ] || remove_conflict 'oversized verification marker'
        record=$(cat "$marker"); digest=${record%%:*}; size=${record#*:}
        case "$digest" in ''|*[!0-9a-f]*) remove_conflict 'invalid digest' ;; esac
        [ "${#digest}" = 64 ] || remove_conflict 'invalid digest length'
        [ "$size" = "$(wc -c < "$binary" | tr -d ' ')" ] || remove_conflict 'program size changed'
        actual=$(sha256sum "$binary"); actual=${actual%% *}
        [ "$actual" = "$digest" ] || remove_conflict 'program bytes changed'
        # Refuse unknown files, including hidden entries, before any deletion.
        for path in "$version_dir"/* "$version_dir"/.[!.]* "$version_dir"/..?*; do
            [ -e "$path" ] || [ -L "$path" ] || continue
            [ "$path" = "$version_dir/bin" ] || remove_conflict 'unknown version contents'
        done
        for path in "$version_dir/bin"/* "$version_dir/bin"/.[!.]* "$version_dir/bin"/..?*; do
            [ -e "$path" ] || [ -L "$path" ] || continue
            case "$path" in "$binary"|"$marker") ;; *) remove_conflict 'unknown program contents' ;; esac
        done
    done
    for pointer in current previous; do
        path="$INSTALLER_PREFIX/$pointer"
        [ -e "$path" ] || [ -L "$path" ] || continue
        [ -L "$path" ] || remove_conflict 'foreign version pointer'
        target=$(readlink "$path")
        case "$target" in versions/*/bin/"$app") ;; *) remove_conflict 'foreign version pointer target' ;; esac
        version=${target#versions/}; version=${version%/bin/"$app"}
        case "$version" in ''|.*|*[!a-zA-Z0-9._+-]*) remove_conflict 'invalid pointer version' ;; esac
        [ -f "$INSTALLER_PREFIX/$target.verified" ] || remove_conflict 'unverified pointer target'
    done
    if [ -e "$INSTALLER_COMMAND" ] || [ -L "$INSTALLER_COMMAND" ]; then
        [ -L "$INSTALLER_COMMAND" ] && [ "$(readlink "$INSTALLER_COMMAND")" = "$INSTALLER_PREFIX/current" ] || remove_conflict 'foreign command entry'
    fi
    # Commit is bounded local filesystem work. Defer termination until its end;
    # never leave a half-unlinked version from a normal cancellation signal.
    trap '' HUP INT TERM
    rm -f "$INSTALLER_COMMAND" "$INSTALLER_PREFIX/current" "$INSTALLER_PREFIX/previous"
    for version_dir in "$INSTALLER_PREFIX"/versions/*; do
        [ -d "$version_dir" ] || continue
        rm "$version_dir/bin/$app" "$version_dir/bin/$app.verified"
        rmdir "$version_dir/bin" "$version_dir"
    done
    rmdir "$INSTALLER_PREFIX/versions"
    rm "$INSTALLER_PREFIX/.managed"
    installer_transaction_finish
    printf 'application=%s\nremoved=true\npreserved=config,data,cache\n' "$app"
}
remove_main "$@"
