# Only query facts cross this interface, never provider manifests or secrets.
def text: if type=="string" then if length>240 then .[0:239]+"…" else . end else . end;
def item:
 {id, name:(.name//.title), description:(.description//.title), source, kind:(.kind//.type//.type_hint),
  installed, installedVersion, availableVersion, candidateVersion, runtimeVersion,
  compatibility, matchReason, scope,
  installedRelease, candidateRelease, functionalValidation,
  evidence:(.evidence//null),
  packages:(if (.packages|type)=="array" then [.packages[:10][]|{name,installedVersion,candidateVersion,sourceConflict}|with_entries(select(.value!=null))] else null end)}
 |with_entries(select(.value!=null))
 |.name|=text |.description|=text |.matchReason|=text
 |with_entries(select(.value!=null));
def rows: if type=="array" then . else [.] end;
rows | map(item) | sort_by(if (.id|ascii_downcase)==($query|ascii_downcase) or ((.name//"")|ascii_downcase)==($query|ascii_downcase) then 0 else 1 end, .id)
| . as $all | {protocol:"software-query/v1",schemaVersion:1,action:$action,targetId:$target,status:$status,nativeExitCode:$native,
 readOnly:true,untrustedData:true,observedAt:(now|todateiso8601),
 truncated:([$all[]|.name,.description,.matchReason|select(type=="string" and endswith("…"))]|length>0),items:.[0:$limit],limit:$limit,hasMore:(length>$limit),reason:$reason,effects:[]}
