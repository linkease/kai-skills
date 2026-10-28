#!/usr/bin/env bash
set -eu
here="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"
. "$here/../../kai-tool-bootstrap/scripts/jq-env.sh"
kai_use_jq full || exit $?
fail() {
    jq -cn --argjson code "$1" --arg category "$2" --arg reason "$3" --argjson native "${4:-null}" --argjson diagnostic "${native_result:-null}" \
      '{schemaVersion:1,status:"failed",category:$category,reason:$reason,nativeExitCode:$native,nativeResult:$diagnostic,exitCode:$code}'
    exit "$1"
}
sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d ' ' -f 1
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d ' ' -f 1
    else return 127; fi
}
client() {
    ks="${KAI_KSCLI_BIN:-$(command -v ks-cli 2>/dev/null || true)}"
    if [ -z "$ks" ]; then
        for candidate in "$HOME/.local/bin/ks-cli" "$HOME/.local/bin/ks-cli.exe"; do
            [ ! -x "$candidate" ] || { ks="$candidate"; break; }
        done
    fi
    if [ -n "$ks" ] && command -v cygpath >/dev/null 2>&1; then ks="$(cygpath -u "$ks")"; fi
    [ -n "$ks" ] && [ -x "$ks" ] || fail 127 missing-executable 'ensure an existing ks-cli first'
}
https_public_url() {
    case "$1" in https://*) ;; *) return 1 ;; esac
    authority="${1#https://}"; authority="${authority%%/*}"
    case "$authority" in ''|*@*|*[$'\n\r\t ']*|*\?*|*\#*) return 1 ;; esac
}
ready() {
    code=0
    if [ "$1" = service ]; then report="$("$ks" doctor --json)" || code=$?
    else report="$("$ks" doctor "$1" --json)" || code=$?; fi
    [ "$code" = 0 ] || fail "$code" acceleration-unavailable 'read-only native Doctor failed' "$code"
    printf '%s' "$report" | jq -e --arg tool "$1" '.schema_version==1 and .tool==$tool and .overall=="pass"' >/dev/null || fail 4 acceleration-unavailable 'native Doctor did not confirm this tool'
}
action="${1:-}"; [ "$#" -gt 0 ] && shift || true
case "$action" in
    doctor)
        [ "$#" = 1 ] || fail 2 usage 'doctor TOOL'
        tool="$1"; client
        case "$tool" in
            file|docker|service) exec "$ks" doctor --json ;;
            git|mise|npm|pip|uv|go|brew) exec "$ks" doctor "$tool" --json ;;
            *) fail 2 usage 'unsupported tool for Doctor' ;;
        esac
        ;;
    explain)
        [ "$#" -ge 3 ] && [ "$2" = -- ] || fail 2 usage 'explain TOOL -- NATIVE_ARGUMENTS...'
        tool="$1"; shift 2
        case "$tool" in git|mise|npm|pip|uv|go|brew|docker) ;; *) fail 2 usage 'unsupported tool for Explain' ;; esac
        client
        exec "$ks" --explain --json "$tool" "$@"
        ;;
    git-clone)
        [ "$#" = 3 ] || fail 2 usage 'git-clone PUBLIC_GITHUB_URL DESTINATION COMMIT'
        url="$1"; dest="$2"; commit="$3"
        [[ "$url" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail 2 source-scope 'this adapter supports public GitHub HTTPS repositories'
        [[ "$commit" =~ ^[a-f0-9]{40}$ ]] || fail 2 integrity 'a complete expected Git commit is required'
        command -v git >/dev/null 2>&1 || fail 127 missing-executable 'native Git is required'
        marker="$dest/.kai-git-managed.json"
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            [ ! -L "$dest" ] && [ -d "$dest" ] && [ -f "$marker" ] && [ ! -L "$marker" ] || fail 4 destination-conflict 'preserve the existing repository or destination'
            jq -e --arg url "$url" --arg commit "$commit" '.schemaVersion==1 and .url==$url and .commit==$commit' "$marker" >/dev/null || fail 4 destination-conflict 'managed clone receipt differs'
            [ "$(git -C "$dest" rev-parse HEAD)" = "$commit" ] && [ "$(git -C "$dest" config --get remote.origin.url)" = "$url" ] && git -C "$dest" diff --quiet HEAD -- || fail 4 destination-conflict 'preserve a changed repository'
            jq -cn --arg path "$dest" --arg commit "$commit" '{schemaVersion:1,status:"reused",operation:"git-clone",path:$path,commit:$commit,contentValidation:"passed",accelerationValidation:"not-run-reused-repository",exitCode:0}'
            exit 0
        fi
        [ -d "$(dirname "$dest")" ] || fail 2 destination 'destination parent must already exist'
        client; ready git
        (umask 077; mkdir -- "$dest") || fail 4 destination-conflict 'cannot reserve a new clone destination'
        owned_dir="$dest"; owned_inode="$(ls -di -- "$dest" | awk '{print $1}')"
        cleanup_git() {
            if [ -n "$owned_dir" ] && [ -d "$owned_dir" ] && [ ! -L "$owned_dir" ] && [ "$(ls -di -- "$owned_dir" | awk '{print $1}')" = "$owned_inode" ]; then
                rm -rf -- "$owned_dir"
            fi
        }
        trap cleanup_git EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM HUP
        code=0; "$ks" git clone --no-checkout -- "$url" "$dest" >&2 || code=$?
        [ "$code" = 0 ] || fail "$code" clone-failed 'native clone failed; inspect original stderr' "$code"
        resolved="$(git -C "$dest" rev-parse --verify "$commit^{commit}" 2>/dev/null)" || fail 4 integrity 'expected commit is absent from the clone'
        [ "$resolved" = "$commit" ] || fail 4 integrity 'Git resolved a different commit'
        code=0; git -C "$dest" -c advice.detachedHead=false checkout --detach "$commit" >&2 || code=$?
        [ "$code" = 0 ] || fail "$code" checkout-failed 'native checkout failed' "$code"
        [ ! -e "$marker" ] && [ ! -L "$marker" ] || fail 4 destination-conflict 'repository contains a conflicting receipt path'
        jq -cn --arg url "$url" --arg commit "$commit" '{schemaVersion:1,url:$url,commit:$commit}' > "$marker"
        tree="$(git -C "$dest" rev-parse 'HEAD^{tree}')"
        owned_dir=''
        jq -cn --arg path "$dest" --arg commit "$commit" --arg tree "$tree" '{schemaVersion:1,status:"passed",operation:"git-clone",path:$path,commit:$commit,tree:$tree,nativeExitCode:0,contentValidation:"passed",accelerationValidation:"pending-current-instance-evidence",exitCode:0}'
        ;;
    docker-pull)
        [ "$#" = 1 ] || fail 2 usage 'docker-pull IMAGE@sha256:DIGEST'
        image="$1"
        [[ "$image" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*@sha256:[a-f0-9]{64}$ ]] || fail 2 integrity 'an OCI image reference with a complete SHA256 digest is required'
        digest="${image##*@}"
        docker_bin="$(command -v docker 2>/dev/null || true)"
        [ -n "$docker_bin" ] && [ -x "$docker_bin" ] || fail 127 missing-executable 'native Docker CLI and an authorized existing daemon are required'
        client; ready service
        code=0; daemon="$("$docker_bin" info --format '{{json .}}')" || code=$?
        [ "$code" = 0 ] || fail "$code" daemon-unavailable 'native Docker info failed' "$code"
        mirror="${KAI_DOCKER_GATEWAY_MIRROR:-https://registry.linkease.net:5443}"
        https_public_url "$mirror" || fail 2 source-scope 'expected daemon mirror must be HTTPS without credentials'
        printf '%s' "$daemon" | jq -e --arg mirror "${mirror%/}" '(.RegistryConfig.Mirrors//[])|any(.[];rtrimstr("/")==$mirror)' >/dev/null || fail 4 acceleration-unavailable 'digest passthrough requires an already configured gateway mirror on the authorized daemon'
        code=0; "$ks" --strict docker pull "$image" >&2 || code=$?
        [ "$code" = 0 ] || fail "$code" pull-failed 'native Docker pull failed; inspect original stderr' "$code"
        code=0; digests="$("$docker_bin" image inspect --format '{{json .RepoDigests}}' "$image")" || code=$?
        [ "$code" = 0 ] || fail "$code" image-verification-failed 'native image inspection failed' "$code"
        printf '%s' "$digests" | jq -e --arg digest "@$digest" 'type=="array" and any(.[];endswith($digest))' >/dev/null || fail 4 integrity 'the resulting image does not report the expected OCI digest' 0
        daemon_summary="$(printf '%s' "$daemon" | jq -ce '{daemonId:.ID,dataRoot:.DockerRootDir,driver:.Driver,mirrors:.RegistryConfig.Mirrors}')" || fail 4 daemon-unavailable 'unsupported Docker info response'
        jq -cn --arg image "$image" --arg digest "$digest" --argjson daemon "$daemon_summary" \
          '{schemaVersion:1,status:"passed",operation:"docker-pull",image:$image,digest:$digest,daemon:$daemon,nativeExitCode:0,contentValidation:"passed",accelerationValidation:"pending-current-instance-evidence",exitCode:0}'
        ;;
    download)
        [ "$#" = 3 ] || fail 2 usage 'download URL DESTINATION SHA256'
        url="$1"; dest="$2"; expected="$3"
        download_mode="${KAI_DOWNLOAD_MODE:-auto}"
        case "$download_mode" in auto|direct|accelerated|race) ;; *) fail 2 usage 'KAI_DOWNLOAD_MODE must be auto, direct, accelerated or race' ;; esac
        https_public_url "$url" || fail 2 source-scope 'a public HTTPS URL without embedded credentials is required'
        [[ "$expected" =~ ^[a-f0-9]{64}$ ]] || fail 2 integrity 'a complete expected SHA256 is required'
        [ ! -L "$dest" ] || fail 4 destination-conflict 'preserve an existing destination symlink'
        if [ -e "$dest" ]; then
            [ -f "$dest" ] || fail 4 destination-conflict 'preserve the existing destination'
            actual="$(sha256 "$dest")" || fail 127 missing-executable 'SHA256 utility unavailable'
            [ "$actual" = "$expected" ] || fail 4 destination-conflict 'preserve an existing file with different content'
            jq -cn --arg path "$dest" --arg sha "$actual" '{schemaVersion:1,status:"reused",operation:"download",path:$path,sha256:$sha,contentValidation:"passed",accelerationValidation:"not-run-reused-file",exitCode:0}'
            exit 0
        fi
        parent="$(dirname "$dest")"; [ -d "$parent" ] || fail 2 destination 'destination parent must already exist'
        client
        staging="$(mktemp "$parent/.kai-download.XXXXXXXX")" || fail 4 staging 'cannot create private staging file'
        trap 'rm -f -- "$staging"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM HUP
        code=0
        native="$("$ks" download --allow-start=false --mode="$download_mode" --json -O "$staging" "$url")" || code=$?
        native_result="$(printf '%s' "$native" | jq -cse 'if length==1 then .[0] else . end' 2>/dev/null)" || native_result=null
        if [ "$code" != 0 ]; then
            [ -z "$native" ] || printf '%s\n' "$native" >&2
            fail "$code" download-failed 'native download failed; inspect original diagnostics' "$code"
        fi
        [ -f "$staging" ] && [ ! -L "$staging" ] || fail 4 integrity 'native command did not produce a regular file' 0
        actual="$(sha256 "$staging")" || fail 127 missing-executable 'SHA256 utility unavailable' 0
        [ "$actual" = "$expected" ] || fail 4 integrity 'download SHA256 differs from the expected content' 0
        # Exclusive activation preserves a destination created by another process.
        ln -- "$staging" "$dest" || fail 4 destination-conflict 'destination appeared or exclusive activation is unavailable' 0
        native_summary=null
        if parsed="$(printf '%s' "$native" | jq -ce '{status,mode,strategy,selected,bytes,attempts:((.attempts//[])|map({type,bytes:(.bytes//0),selected:(.selected//false),errorKind:.error_kind,httpStatus:.http_status}))}' 2>/dev/null)"; then native_summary="$parsed"; fi
        validation=pending-current-instance-evidence
        if printf '%s' "$native_summary" | jq -e '.selected == "origin"' >/dev/null; then validation=direct-selected-no-acceleration-claim; fi
        jq -cn --arg path "$dest" --arg sha "$actual" --argjson native "$native_summary" --arg validation "$validation" \
          '{schemaVersion:1,status:"passed",operation:"download",path:$path,sha256:$sha,nativeExitCode:0,contentValidation:"passed",accelerationValidation:$validation,download:$native,exitCode:0}'
        ;;
    *) fail 2 usage 'supported actions: download, git-clone, docker-pull, doctor, explain' ;;
esac
