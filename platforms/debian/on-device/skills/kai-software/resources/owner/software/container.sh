# Curated stateless application owner. Docker owns image transport and digest verification.
task_docker() { env -u DOCKER_HOST -u DOCKER_CONTEXT docker --context default "$@"; }
task_container_engine() {
    local context info code host
    type -P docker >/dev/null || task_stop blocked missing-docker-engine 127
    context=$(task_docker context inspect default);code=$?
    [ "$code" = 0 ] || task_stop failed docker-context-query-failed "$code"
    host=$("$task_jq" -r '.[0].Endpoints.docker.Host//""' <<< "$context")
    case "$host" in unix:///*) ;; *) task_stop blocked nonlocal-docker-context 0 ;; esac
    info=$(task_docker info --format '{{json .}}');code=$?
    [ "$code" = 0 ] || task_stop blocked docker-engine-unavailable "$code"
    [ "$("$task_jq" -r .OSType <<< "$info")" = linux ] || task_stop blocked unsupported-container-engine 0
    [ -r /proc/sys/kernel/hostname ] && [ "$(cat /proc/sys/kernel/hostname)" = "$("$task_jq" -r .Name <<< "$info")" ] || task_stop blocked docker-target-identity-unverified 0
    TASK_CONTAINER_ENGINE=$("$task_jq" -c '{id:.ID,name:.Name,dataRoot:.DockerRootDir,architecture:.Architecture,os:.OSType}' <<< "$info")
    "$task_jq" -e '.id|type=="string" and length>0' <<< "$TASK_CONTAINER_ENGINE" >/dev/null || task_stop failed invalid-docker-identity 11
}
task_container_owned_directory() {
    local app=$1 identity=$2
    [ ! -L "$app" ] || task_stop blocked unsafe-container-directory 0
    if [ -e "$app" ]; then
        [ -d "$app" ] && [ -f "$app/.managed" ] && [ ! -L "$app/.managed" ] && [ "$(cat "$app/.managed")" = "$identity" ] || task_stop blocked container-directory-unowned 0
        local child
        for child in data nginx.conf .managed; do [ ! -L "$app/$child" ] || task_stop blocked unsafe-container-directory 0; done
    fi
}
task_container_inspect() {
    local name=$1 owner=$2 data=$3 config=$4 raw code
    raw=$(task_docker container inspect "$name" 2>&1);code=$?
    if [ "$code" != 0 ]; then
        case "$raw" in *'No such container'*|*'No such object'*) TASK_CONTAINER_OBSERVED=null;return ;; esac
        printf '%s\n' "$raw" >&2;task_stop failed container-inspect-failed "$code"
    fi
    "$task_jq" -e --arg owner "$owner" --arg data "$data" --arg config "$config" '
      length==1 and (.[0]|.Config.Labels["io.kaiplus.owner"]==$owner and
      any(.Mounts[];.Source==$data and .Destination=="/usr/share/nginx/html" and .RW==false) and
      any(.Mounts[];.Source==$config and .Destination=="/etc/nginx/nginx.conf" and .RW==false))' <<< "$raw" >/dev/null || task_stop blocked container-name-or-mount-unowned 0
    TASK_CONTAINER_OBSERVED=$("$task_jq" -c '.[0]|{id:.Id,image:.Image,running:.State.Running,name:(.Name|ltrimstr("/"))}' <<< "$raw")
}
task_container_network() {
    local name=$1 owner=$2 raw code
    raw=$(task_docker network inspect "$name" 2>&1);code=$?
    if [ "$code" != 0 ]; then
        case "$raw" in *'No such network'*|*'not found'*) TASK_CONTAINER_NETWORK=null;return ;; esac
        printf '%s\n' "$raw" >&2;task_stop failed container-network-query-failed "$code"
    fi
    "$task_jq" -e --arg owner "$owner" 'length==1 and (.[0]|.Driver=="bridge" and .Labels["io.kaiplus.owner"]==$owner)' <<< "$raw" >/dev/null || task_stop blocked container-network-unowned 0
    TASK_CONTAINER_NETWORK=$("$task_jq" -c '.[0]|{id:.Id,name:.Name,driver:.Driver}' <<< "$raw")
}
task_container_plan() {
    local input method=container intent image source version arch base id app name engine_root body effects data_bytes observed ids previous='[]' resource
    input=$(task_request_digest);intent=$("$task_jq" -r '.intent//"install"' <<< "$TASK_REQUEST_JSON")
    case "$intent" in install|remove) ;; *) task_stop invalid invalid-intent 2 ;; esac
    [ "$TASK_SOFTWARE" = nginx-static ] || task_stop needs-ai container-application-recipe-required 0
    [ "$("$task_jq" -r '.container.start//false' <<< "$TASK_REQUEST_JSON")" = true ] || task_stop blocked container-start-not-selected 0
    image=$("$task_jq" -r '.container.image//""' <<< "$TASK_REQUEST_JSON")
    # Immutable official manifest identities observed through Docker's own verifier.
    case "$image" in
      nginx@sha256:0985e772fb9f729e6fa0980da05fca5d9c468e870eed43071545afa9d2e27d94) version=1.30.5 ;;
      nginx@sha256:db35bfc6b2951e7f8a72db5db120288c127ffaeeb4a6d4b95a26fead017d5913) version=1.31.4 ;;
      *) task_stop needs-ai container-image-recipe-required 0 ;;
    esac
    task_version_matches "$("$task_jq" -r '.version//""' <<< "$TASK_REQUEST_JSON")" "$version" || task_stop needs-ai no-compatible-container-version 0
    source=$("$task_jq" -r '.container.source//"official"' <<< "$TASK_REQUEST_JSON")
    case "$source" in official) source=$image ;; linkease-mirror) source=registry.linkease.net:5443/library/$image ;; *) task_stop needs-ai unknown-container-source 0 ;; esac
    "$task_jq" -e '(.container.dataBytes|type=="number" and .>=1048576 and .<=1000000000000 and floor==.) and ((.features//[])|length==0)' <<< "$TASK_REQUEST_JSON" >/dev/null || task_stop invalid invalid-container-budget-or-features 2
    task_container_engine
    arch=$("$task_jq" -r .architecture <<< "$TASK_CONTAINER_ENGINE")
    case "$arch" in x86_64|amd64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) task_stop needs-ai unsupported-container-architecture 0 ;; esac
    base=$("$task_jq" -r '.container.baseDir//""' <<< "$TASK_REQUEST_JSON")
    id=$(printf '%s\n%s\n%s\n' "$TASK_TARGET" "$base" "$("$task_jq" -r .id <<< "$TASK_CONTAINER_ENGINE")" | task_hash_input)
    name=kai-nginx-${id:0:16};app=${base%/}/$name
    task_container_owned_directory "$app" "$id"
    task_container_network "$name-net" "$id"
    task_container_inspect "$name" "$id" "$app/data" "$app/nginx.conf";observed=$TASK_CONTAINER_OBSERVED
    # Snapshot only exact ownership labels; shared images and other containers stay outside this owner.
    ids=$(task_docker ps -aq --filter "label=io.kaiplus.owner=$id");resource=$?
    [ "$resource" = 0 ] || task_stop failed container-list-failed "$resource"
    for resource in $ids; do
        task_container_inspect "$resource" "$id" "$app/data" "$app/nginx.conf"
        previous=$("$task_jq" -cn --argjson rows "$previous" --argjson row "$TASK_CONTAINER_OBSERVED" '$rows+[$row]')
    done
    previous=$("$task_jq" -c 'sort_by(.id)' <<< "$previous")
    engine_root=$("$task_jq" -r .dataRoot <<< "$TASK_CONTAINER_ENGINE")
    data_bytes=$("$task_jq" .container.dataBytes <<< "$TASK_REQUEST_JSON")
    TASK_REQUEST_JSON=$("$task_jq" -c --arg root "$engine_root" --arg base "$base" --argjson bytes "$data_bytes" '.storage={reserveBytes:8388608,paths:[{role:"container-image-unpack-and-retention",path:$root,bytes:536870912,inodes:128},{role:"container-data-and-config",path:$base,bytes:($bytes+1048576),inodes:32}]}' <<< "$TASK_REQUEST_JSON")
    if [ "$intent" = remove ]; then
        TASK_REQUEST_JSON=$("$task_jq" -c '.storage.paths|=map(.bytes=65536|.inodes=0)' <<< "$TASK_REQUEST_JSON")
    fi
    task_storage_plan
    local storage=$TASK_STORAGE_PLAN backup=null combined=null saved
    if [ "$intent" != remove ] && [ "$("$task_jq" -r '.backupRequired//false' <<< "$TASK_REQUEST_JSON")" = true ]; then
        task_backup_plan;backup=$TASK_BACKUP_PLAN
        saved=$TASK_REQUEST_JSON;task_backup_add_budget;task_storage_plan;combined=$TASK_STORAGE_PLAN;TASK_REQUEST_JSON=$saved
    fi
    effects='["create-owned-bridge-if-missing","docker-image-pull-if-missing","managed-container-files","container-create-and-start","retain-old-image-and-data"]'
    [ "$intent" != remove ] || effects='["remove-owned-containers","retain-images-and-data"]'
    body=$("$task_jq" -cn --arg input "$input" --arg request "$(task_request_digest)" --arg owner "$(task_owner_digest)" --arg intent "$intent" --arg app "$app" --arg id "$id" --arg name "$name" --arg image "$image" --arg source "$source" --arg version "$version" --arg arch "$arch" --argjson network "$TASK_CONTAINER_NETWORK" --argjson engine "$TASK_CONTAINER_ENGINE" --argjson observed "$observed" --argjson resources "$previous" --argjson storage "$storage" --argjson backup "$backup" --argjson combined "$combined" --argjson effects "$effects" '{method:"container",intent:$intent,inputDigest:$input,requestDigest:$request,ownerDigest:$owner,appDir:$app,ownerId:$id,name:$name,image:{reference:$image,source:$source,version:$version,architecture:$arch,maxExpandedBytes:134217728},engine:$engine,ownedNetwork:$network,networkPolicy:"dedicated-owned-bridge",observed:$observed,ownedContainers:$resources,security:{user:"101:101",readOnlyRoot:true,capabilities:"drop-all",noNewPrivileges:true,pidsLimit:64,memoryBytes:134217728,dataMount:"read-only"},endpointPolicy:"loopback-ephemeral",health:{method:"HTTP GET /",port:8080,deadlineSeconds:15},dataRollback:"separate-file-backup-required",storagePlan:$storage,backupPlan:$backup,combinedStoragePlan:$combined,effects:$effects}')
    TASK_PLAN=$("$task_jq" -c --arg digest "$("$task_jq" -cS . <<< "$body" | task_hash_input)" '.+{planDigest:$digest}' <<< "$body")
}
task_container_health() {
    local name=$1 n=0
    while [ "$n" -lt 15 ]; do
        task_docker exec "$name" wget -q -O /dev/null http://127.0.0.1:8080/ >/dev/null 2>&1 && return 0
        sleep 1;n=$((n+1))
    done
    return 1
}
task_container_run() {
    local name=$1 image=$2 app=$3 owner=$4
    task_docker run -d --name "$name" --label "io.kaiplus.owner=$owner" \
      --network "${name%%-candidate-*}-net" --read-only --user 101:101 --cap-drop ALL --security-opt no-new-privileges \
      --pids-limit 64 --memory 134217728 --tmpfs /tmp:rw,noexec,nosuid,size=16777216 \
      --mount "type=bind,src=$app/data,dst=/usr/share/nginx/html,readonly" \
      --mount "type=bind,src=$app/nginx.conf,dst=/etc/nginx/nginx.conf,readonly" \
      -p 127.0.0.1::8080 --entrypoint nginx "$image" -c /etc/nginx/nginx.conf -g 'daemon off;'
}
task_container_apply() {
    local expected=$1 app owner name candidate previous image code=0 raw id current lock result port
    app=$("$task_jq" -r .appDir <<< "$expected");owner=$("$task_jq" -r .ownerId <<< "$expected");name=$("$task_jq" -r .name <<< "$expected")
    lock=${app}.lock
    (umask 077;mkdir "$lock") || task_stop blocked container-operation-in-progress 0
    TASK_CONTAINER_LOCK=$lock
    trap 'rmdir "$TASK_CONTAINER_LOCK" 2>/dev/null || true' EXIT
    task_container_owned_directory "$app" "$owner"
    # Serialize this owner, then re-resolve to catch another request that completed while waiting.
    task_container_plan
    [ "$("$task_jq" -cS '.ownedContainers' <<< "$expected")" = "$("$task_jq" -cS '.ownedContainers' <<< "$TASK_PLAN")" ] || task_stop blocked container-state-changed 0
    [ "$("$task_jq" -cS .ownedNetwork <<< "$expected")" = "$("$task_jq" -cS .ownedNetwork <<< "$TASK_PLAN")" ] || task_stop blocked container-network-changed 0
    task_storage_check "$("$task_jq" -c .storagePlan <<< "$expected")"
    if [ "$("$task_jq" -r .intent <<< "$expected")" = remove ]; then
        TASK_EFFECTS='["remove-owned-containers"]'
        while IFS= read -r id; do
            [ -n "$id" ] || continue
            task_docker rm -f "$id" >&2 || task_stop failed container-remove-failed "$?"
        done < <("$task_jq" -r '.ownedContainers[].id' <<< "$expected")
        if [ "$("$task_jq" -c .ownedNetwork <<< "$expected")" != null ]; then
            task_docker network rm "$name-net" >&2 || task_stop failed container-network-remove-failed "$?"
        fi
        task_result success removed 0 '{"preserved":["data","images","configuration"],"dataRollback":"separate-file-backup-required"}' "$TASK_EFFECTS";return
    fi
    image=$("$task_jq" -r .image.source <<< "$expected")
    raw=$(task_docker image inspect "$image" 2>&1);code=$?
    if [ "$code" != 0 ]; then
        case "$raw" in *'No such image'*|*'No such object'*) ;;
          *) printf '%s\n' "$raw" >&2;task_stop failed container-image-query-failed "$code" ;; esac
        TASK_EFFECTS='["docker-image-pull-attempt"]'
        local zsetup
        zsetup=${ZSETUP_BIN:-${KAI_ZSETUP_BIN:-$(type -P zsetup || true)}}
        [ -n "$zsetup" ] || { [ ! -x "$HOME/.local/bin/zsetup" ] || zsetup=$HOME/.local/bin/zsetup; }
        [ -n "$zsetup" ] && [ -x "$zsetup" ] || task_stop blocked bounded-container-download-needs-zsetup 127
        code=0
        "$zsetup" capture -o "$lock/image-pull.log" --max-bytes 1048576 --timeout 180s -- env -u DOCKER_HOST -u DOCKER_CONTEXT docker --context default pull "$image" >&2 || code=$?
        [ ! -f "$lock/image-pull.log" ] || { cat "$lock/image-pull.log" >&2;rm -f "$lock/image-pull.log"; }
        [ "$code" = 0 ] || task_stop failed container-image-pull-failed "$code"
        raw=$(task_docker image inspect "$image") || task_stop failed container-image-query-failed "$?"
    fi
    "$task_jq" -e --arg arch "$("$task_jq" -r .image.architecture <<< "$expected")" --arg version "$("$task_jq" -r .image.version <<< "$expected")" --arg digest "${image##*@}" 'length==1 and (.[0]|.Os=="linux" and .Architecture==$arch and .Size<=134217728 and any(.RepoDigests[];endswith("@"+$digest)) and any(.Config.Env[];.==("NGINX_VERSION="+$version)))' <<< "$raw" >/dev/null || task_stop failed container-image-verification-failed 11
    id=$("$task_jq" -r '.[0].Id' <<< "$raw")
    current=$("$task_jq" -r '.observed.image//""' <<< "$expected")
    if [ "$current" = "$id" ]; then
        task_container_health "$name" || task_stop failed existing-container-unhealthy 11
        task_result success reused 0 '{"functionalValidation":"passed","dataPreserved":true}';return
    fi
    TASK_EFFECTS='["owned-container-network","managed-container-files","container-start-attempt"]'
    if [ "$("$task_jq" -c .ownedNetwork <<< "$expected")" = null ]; then
        task_docker network create --driver bridge --label "io.kaiplus.owner=$owner" "$name-net" >&2 || task_stop failed container-network-create-failed "$?"
    fi
    if [ ! -e "$app" ]; then
        (umask 022;mkdir "$app" && printf '%s\n' "$owner" > "$app/.managed" && mkdir "$app/data" && printf '%s\n' 'KaiPlus managed static site' > "$app/data/index.html") || task_stop failed container-directory-create-failed "$?"
        cat > "$app/nginx.conf" <<'NGINX'
worker_processes 1;
pid /tmp/nginx.pid;
error_log /dev/stderr warn;
events { worker_connections 64; }
http {
  access_log /dev/stdout;
  client_body_temp_path /tmp/client;
  proxy_temp_path /tmp/proxy;
  fastcgi_temp_path /tmp/fastcgi;
  uwsgi_temp_path /tmp/uwsgi;
  scgi_temp_path /tmp/scgi;
  server { listen 8080; root /usr/share/nginx/html; location / { try_files $uri $uri/ =404; } }
}
NGINX
        chmod 644 "$app/nginx.conf" || task_stop failed container-config-permission-failed "$?"
    fi
    candidate=$name-candidate-${RANDOM}-${RANDOM}
    task_container_run "$candidate" "$id" "$app" "$owner" >&2 || {
        code=$?
        task_container_inspect "$candidate" "$owner" "$app/data" "$app/nginx.conf"
        if [ "$TASK_CONTAINER_OBSERVED" != null ]; then task_docker rm -f "$candidate" >&2 || task_stop failed container-candidate-cleanup-failed "$?";fi
        task_stop failed container-create-failed "$code"
    }
    if ! task_container_health "$candidate"; then
        task_docker rm -f "$candidate" >&2 || task_stop failed container-candidate-cleanup-failed "$?"
        task_stop failed container-health-failed 11 '{"oldContainerPreserved":true,"dataRestored":false}'
    fi
    previous=$("$task_jq" -r '.observed.id//""' <<< "$expected")
    if [ -n "$previous" ]; then
        task_docker rename "$previous" "$name-previous-${previous:0:12}" >&2 || { code=$?;task_docker rm -f "$candidate" >&2;task_stop failed container-activation-failed "$code"; }
    fi
    if ! task_docker rename "$candidate" "$name" >&2; then
        [ -z "$previous" ] || task_docker rename "$previous" "$name" >&2
        task_docker rm -f "$candidate" >&2
        task_stop failed container-activation-failed 11
    fi
    if [ -n "$previous" ]; then
        if ! task_docker stop "$previous" >&2; then
            task_docker rename "$name" "$candidate" >&2
            task_docker rename "$previous" "$name" >&2
            task_docker rm -f "$candidate" >&2
            task_stop failed old-container-stop-failed 11
        fi
    fi
    port=$(task_docker port "$name" 8080/tcp) || task_stop failed container-endpoint-query-failed "$?"
    result=$("$task_jq" -cn --arg name "$name" --arg image "$id" --arg endpoint "$port" '{container:$name,imageId:$image,functionalValidation:"passed",endpoint:$endpoint,dataPreserved:true,oldContainerRetained:true,dataRollback:"separate-file-backup-required"}')
    task_result success installed 0 "$result" "$TASK_EFFECTS"
}
