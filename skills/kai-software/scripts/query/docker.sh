# Docker catalog scope is explicit: local images/containers, never a registry.
query_docker() {
 command -v docker >/dev/null 2>&1 || fail missing-docker
 local context
 context=$(env -u DOCKER_HOST -u DOCKER_CONTEXT docker --context default context inspect default 2>"$work/private.log") || fail docker-context-unavailable
 printf '%s' "$context" | jq -e '.[0].Endpoints.docker.Host|startswith("unix:///")' >/dev/null || fail nonlocal-docker-context
 env -u DOCKER_HOST -u DOCKER_CONTEXT docker --context default image ls --digests --no-trunc --format '{{json .}}' >"$work/images" 2>"$work/private.log" || fail docker-query-failed
 env -u DOCKER_HOST -u DOCKER_CONTEXT docker --context default container ls --all --no-trunc --format '{{json .}}' >"$work/containers" 2>"$work/private.log" || fail docker-query-failed
 jq -sc '[.[]|{id:("docker-image:"+.ID),name:(.Repository+":"+.Tag),source:"docker-local",kind:"image",scope:"local-images",evidence:{digest:.Digest,imageId:.ID,candidateVersion:"unknown"}}]' "$work/images" >"$work/image-rows"
 jq -sc '[.[]|{id:("docker-container:"+.ID),name:.Names,source:"docker-local",kind:"container",scope:"local-containers",evidence:{image:.Image,state:.State,candidateVersion:"unknown"}}]' "$work/containers" >"$work/container-rows"
 jq -sc --arg q "$query" --arg action "$action" 'add|map(select(if $action=="search" then ((.id+" "+.name)|ascii_downcase|contains($q|ascii_downcase)) else .id==$q end))' "$work/image-rows" "$work/container-rows"
}
