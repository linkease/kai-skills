# Source only after the target runtime HOME has been established.
python_openssl_environment() {
    [ "${OPENSSL_CONF+x}" != x ] || return 0
    local pc_here="$1" pc_root="${ISTORE_SYSTEM_ROOT:-}" pc_source pc_digest pc_expected pc_file pc_dir pc_target pc_stage
    pc_source="$pc_root/etc/ssl/openssl.cnf"
    [ -f "$pc_source" ] || return 0
    pc_digest="$(sha256sum "$pc_source")"; pc_digest="${pc_digest%% *}"
    pc_expected="$(jq -er .originalSha256 "$pc_here/../references/python-openssl.lock.json")"
    # Custom system policy is never translated by a default-firmware adapter.
    [ "$pc_digest" = "$pc_expected" ] || return 0
    [ ! -L "$pc_root/etc/ssl/modules.cnf.d" ] || fail 4 openssl-config-conflict 'firmware crypto extension directory is an external link'
    for pc_file in "$pc_root/var/etc/ssl/engines.cnf" "$pc_root/var/etc/ssl/providers.cnf" \
                   "$pc_root"/etc/ssl/modules.cnf.d/* "$pc_root"/etc/ssl/modules.cnf.d/.[!.]* "$pc_root"/etc/ssl/modules.cnf.d/..?*; do
        [ -e "$pc_file" ] || [ -L "$pc_file" ] || continue
        [ -f "$pc_file" ] && [ ! -L "$pc_file" ] || fail 4 openssl-config-conflict 'custom firmware crypto extensions need a compatible SDK; system configuration is preserved'
        if [ "$pc_file" = "$pc_root/etc/ssl/modules.cnf.d/legacy.cnf" ]; then
            pc_digest="$(sha256sum "$pc_file")"; pc_digest="${pc_digest%% *}"
            pc_expected="$(jq -er .inactiveLegacySha256 "$pc_here/../references/python-openssl.lock.json")"
            # This exact factory section is unreferenced by the locked base
            # configuration. All other extension files must remain empty;
            # in particular providers.cnf may not enable this legacy section.
            [ "$pc_digest" != "$pc_expected" ] || continue
        fi
        if grep -Eq '^[[:space:]]*[^[:space:]#;]' "$pc_file"; then
            fail 4 openssl-config-conflict 'active firmware crypto policy cannot be replaced by the default Python adapter'
        fi
    done
    pc_expected="$(jq -er .pythonSha256 "$pc_here/../references/python-openssl.lock.json")"
    pc_dir="$HOME/.local/share/kai/python-openssl"
    [ ! -L "$pc_dir" ] || fail 11 openssl-config-conflict 'Python configuration cache is an external link'
    (umask 077; mkdir -p "$pc_dir") || fail 12 filesystem-failed 'cannot prepare the private Python configuration cache'
    pc_target="$pc_dir/$pc_expected.cnf"
    if [ -e "$pc_target" ] || [ -L "$pc_target" ]; then
        [ -f "$pc_target" ] && [ ! -L "$pc_target" ] || fail 11 openssl-config-conflict 'Python compatibility configuration is not an owned regular file'
        pc_digest="$(sha256sum "$pc_target")"; pc_digest="${pc_digest%% *}"
        [ "$pc_digest" = "$pc_expected" ] || fail 11 openssl-config-conflict 'Python compatibility configuration was modified; preserve and inspect it'
    else
        pc_stage="$(mktemp "$pc_dir/.candidate.XXXXXX")" || fail 12 filesystem-failed 'cannot stage Python configuration'
        sed 's/^engines = engines_sect$/# Empty firmware ENGINE initialization omitted for the bundled Python OpenSSL./' "$pc_source" > "$pc_stage"
        pc_digest="$(sha256sum "$pc_stage")"; pc_digest="${pc_digest%% *}"
        if [ "$pc_digest" != "$pc_expected" ]; then rm -f "$pc_stage"; fail 11 integrity-failed 'Python compatibility configuration digest mismatch'; fi
        mv "$pc_stage" "$pc_target" || { rm -f "$pc_stage"; fail 12 filesystem-failed 'cannot activate Python configuration'; }
    fi
    # Only this Python task and its children inherit the copy. Firmware files,
    # providers, CA roots, config_diagnostics and SSL validation remain intact.
    export OPENSSL_CONF="$pc_target"
}
