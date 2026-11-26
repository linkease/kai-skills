#!/usr/bin/env bash
# Sourced after the caller's JSON fail() and complete jq selection.
kai_runtime_adapter() {
    local directory="$here/../resources/istore-runtime" expected actual member
    jq -e '.schemaVersion == 1 and (.files | keys == ["environment.sh","exec.sh"])' \
        "$directory/source.lock.json" >/dev/null 2>&1 || fail 11 integrity-failed 'the native runtime source lock is missing or invalid'
    for member in exec.sh environment.sh; do
        expected="$(jq -er --arg name "$member" '.files[$name]' "$directory/source.lock.json")" || fail 11 integrity-failed 'native runtime resource digest is absent'
        [ -f "$directory/$member" ] && [ ! -L "$directory/$member" ] || fail 11 integrity-failed 'native runtime resource is absent or aliased'
        if command -v sha256sum >/dev/null 2>&1; then actual="$(sha256sum "$directory/$member")";
        else actual="$(shasum -a 256 "$directory/$member")"; fi
        [ "${actual%% *}" = "$expected" ] || fail 11 integrity-failed 'the native runtime resource differs from its owner snapshot'
    done
    adapter="$directory/exec.sh"
}
