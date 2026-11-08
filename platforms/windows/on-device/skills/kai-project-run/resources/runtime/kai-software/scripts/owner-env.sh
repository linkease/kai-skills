# Source from Bash after selecting full jq; prints one verified library root.
kai_software_owner_root() {
    local directory path result
    directory=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../resources" && pwd -P) || return 11
    jq -e '.schemaVersion==1 and .owner=="zsetup-scripts" and .protocol=="software-task/v1" and
      (.sourceCommit|test("^[a-f0-9]{40}$")) and
      (.files|type=="array" and length>0 and all(.[];
        (.file|test("^owner/[A-Za-z0-9/._-]+$") and (split("/")|all(.[];.!="." and .!=".."))) and
        (.sha256|test("^[a-f0-9]{64}$")) and (.size|type=="number" and .>0)))' \
      "$directory/software-owner.lock.json" >/dev/null || return 11
    for path in owner owner/software owner/jq;do [ ! -L "$directory/$path" ] || return 11;done
    while IFS= read -r path;do
        [ -f "$directory/$path" ] && [ ! -L "$directory/$path" ] || return 11
    done < <(jq -r '.files[].file' "$directory/software-owner.lock.json")
    result=0
    if command -v sha256sum >/dev/null 2>&1;then
        (cd "$directory" && jq -r '.files[]|(.sha256+"  "+.file)' software-owner.lock.json | sha256sum -c - >/dev/null) || result=$?
    else
        (cd "$directory" && jq -r '.files[]|(.sha256+"  "+.file)' software-owner.lock.json | shasum -a 256 -c - >/dev/null) || result=$?
    fi
    [ "$result" = 0 ] || return 11
    printf '%s\n' "$directory/owner"
}
