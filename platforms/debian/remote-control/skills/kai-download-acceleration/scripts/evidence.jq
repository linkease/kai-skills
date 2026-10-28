def epoch:
  capture("^(?<whole>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(?:\\.(?<fraction>[0-9]{1,9}))?Z$") |
  ((.whole+"Z"|fromdateiso8601) + ("0."+(.fraction//"0")|tonumber));
def sha: type=="string" and test("^[a-f0-9]{64}$");
def incomplete($m;$reason;$missing):
  {schemaVersion:1,status:"partial",operation:"verify-evidence",channel:$m.channel,
   contentValidation:$m.client.contentValidation,functionalValidation:$m.client.functionalValidation,
   accelerationValidation:$reason,missingRequests:$missing,exitCode:4};
$manifest[0] as $m |
if ($manifest|length)!=1 or $m.schemaVersion!=1 or
   (["file","git","docker","sdk-python","sdk-node","sdk-go","npm","pip","uv","go-modules"]|index($m.channel))==null or
   ($m.instanceId|type)!="string" or ($m.instanceId|length)==0 or
   ($m.tlsPort|type)!="number" or $m.tlsPort<1 or $m.tlsPort>65535 or
   ($m.window.startUnix|type)!="number" or ($m.window.endUnix|type)!="number" or $m.window.endUnix<$m.window.startUnix or
   ($m.requests|type)!="array" or ($m.requests|length)==0
then error("invalid proof manifest") else . end |
if $m.client.exitCode!=0 or $m.client.contentValidation!="passed" or
   ($m.client.functionalValidation!="passed" and ($m.channel!="file" or $m.client.functionalValidation!="not-required")) or
   ($m.client.directObserved|type)!="boolean" or $m.client.logSha256!=$clientSha
then incomplete($m;"client-not-verified";[]) else
if $m.client.directObserved==true then incomplete($m;"client-direct-observed";[]) else
(["artifact"] + (if $m.channel=="file" then [] else ["metadata"] end)) as $roles |
if any($roles[]; . as $role | all($m.requests[]; .role!=$role))
then incomplete($m;"missing-required-request-definitions";$roles) else
[$logs|split("\n")[]|select(startswith("download observation "))|ltrimstr("download observation ")|fromjson] as $events |
($m.requests|map(. as $request |
   (if .role=="artifact" and (.sha256|sha|not) and
       ($m.channel!="git" or ($m.expected.commit|type)!="string" or
        ($m.expected.commit|test("^[a-f0-9]{40}$")|not) or $m.client.commit!=$m.expected.commit)
    then error("artifact needs an independent digest or verified Git commit") else . end) |
   [$events[]|select(.schemaVersion==1 and .instanceId==$m.instanceId and .listenPort==$m.tlsPort and .tls==true and
       .method==$request.method and .host==$request.host and .path==$request.path and
       .status>=200 and .status<300 and .bytes>0 and .transportCompleted==true and (.sha256|sha) and
       (.startedAt|epoch)>=$m.window.startUnix and (.finishedAt|epoch)<=$m.window.endUnix and
       ($request.sha256==null or .sha256==$request.sha256))] as $matched |
   {request:$request,events:$matched})) as $matches |
[$matches[]|select((.events|length)==0)|.request] as $missing |
if ($missing|length)>0 then incomplete($m;"insufficient-evidence";$missing) else
if $m.requireCold==true and ($m.client.cacheCold!=true or $m.gatewayFresh!=true or
   any($events[]; . as $e | .instanceId==$m.instanceId and (.finishedAt|epoch)<$m.window.startUnix and
       any($m.requests[]; .host==$e.host and .path==$e.path and .method==$e.method)))
then incomplete($m;"cold-cache-state-unconfirmed";[]) else
{schemaVersion:1,status:"passed",operation:"verify-evidence",channel:$m.channel,
 contentValidation:$m.client.contentValidation,functionalValidation:$m.client.functionalValidation,
 accelerationValidation:"confirmed",instanceId:$m.instanceId,tlsPort:$m.tlsPort,
 cacheScope:(if $m.requireCold==true then "client-and-gateway-resource-cold" else "not-asserted" end),
 clientLogSha256:$clientSha,gatewayLogSha256:$gatewaySha,
 matchedRequests:[$matches[]|{role:.request.role,host:.request.host,path:.request.path,
     requestIds:[.events[].requestId],sha256:[.events[].sha256]}],exitCode:0}
end end end end end
