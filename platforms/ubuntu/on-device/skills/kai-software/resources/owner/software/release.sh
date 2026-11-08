# Fixed owner recipe metadata. Native zsetup remains the download implementation.
task_release_plan() {
    local input recipe artifact platform wanted version base
    if [ "$#" -gt 0 ];then input=$1;else input=$(task_request_digest);fi
    if [ "$("$task_jq" -r '.intent//"install"' <<< "$TASK_REQUEST_JSON")" = remove ];then
        task_artifact_plan release "$input";return
    fi
    task_artifact_platform || task_stop needs-ai artifact-platform-unrecognized 0
    platform=$TASK_ARTIFACT_PLATFORM
    recipe=$("$task_jq" -c --arg software "$TASK_SOFTWARE" '.software[$software]//null' < "$task_root/releases.lock.json")
    [ "$recipe" != null ] || task_stop needs-ai no-release-recipe 0
    "$task_jq" -e '(.version|type=="string" and test("^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$")) and
      (.sourceCommit|type=="string" and test("^[a-f0-9]{40}$")) and
      (.features|type=="array" and all(.[];type=="string")) and
      (.verifyArgs|type=="array" and length<=32 and all(.[];type=="string")) and
      (.expectedOutput|type=="string" and length>0)' <<< "$recipe" >/dev/null || task_stop failed invalid-release-recipe 11
    wanted=$("$task_jq" -r '.version//""' <<< "$TASK_REQUEST_JSON");version=$("$task_jq" -r .version <<< "$recipe")
    [ -z "$wanted" ] || [ "$wanted" = "$version" ] || task_stop needs-ai no-compatible-release-version 0
    "$task_jq" -e --argjson recipe "$recipe" '(.features//[])|all(.[];. as $name|$recipe.features|index($name)!=null)' <<< "$TASK_REQUEST_JSON" >/dev/null || task_stop needs-ai unknown-functional-requirement 0
    artifact=$("$task_jq" -c --arg platform "$platform" '.artifacts[$platform]//null' <<< "$recipe")
    [ "$artifact" != null ] || task_stop needs-ai no-verified-release-artifact 0
    "$task_jq" -e '(.url|type=="string" and startswith("https://") and (test("[\r\n]")|not)) and
      (.sha256|type=="string" and test("^[a-f0-9]{64}$")) and
      (.size|type=="number" and floor==. and .>0 and .<=268435456)' <<< "$artifact" >/dev/null || task_stop failed invalid-release-artifact 11
    base=$("$task_jq" -r '.prefixBase//""' <<< "$TASK_REQUEST_JSON")
    [ -n "$base" ] && [ -d "$base" ] || task_stop needs-ai persistent-installation-location-required 0
    TASK_REQUEST_JSON=$("$task_jq" -c --arg version "$version" --arg platform "$platform" --argjson artifact "$artifact" --argjson recipe "$recipe" '
      .version=$version|.artifact=($artifact+{path:"",platform:$platform,verifyArgs:$recipe.verifyArgs,
      expectedOutput:$recipe.expectedOutput,sourceCommit:$recipe.sourceCommit})' <<< "$TASK_REQUEST_JSON")
    task_artifact_plan release "$input"
}
