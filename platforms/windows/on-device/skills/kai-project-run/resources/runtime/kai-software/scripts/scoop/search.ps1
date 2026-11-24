# Caller verifies ownership and module digest before reading bucket manifests.
function Scoop-Search([string]$root,[string]$subject,[int]$searchLimit) {
        $buckets=@(Get-ChildItem -LiteralPath (Join-Path $root 'buckets') -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name | Where-Object {$_.Name -match '^[A-Za-z0-9][A-Za-z0-9._-]*$'})
        $searchMatches=@()
        # Check exact names across sources before scanning descriptions. A busy
        # first bucket must not hide an exact name in a later bucket.
        if($subject -match '^[A-Za-z0-9][A-Za-z0-9._-]*$'){
            foreach($bucket in $buckets){
                if(Test-Path -LiteralPath (Join-Path $bucket.FullName ("bucket\$subject.json")) -PathType Leaf){
                    $searchMatches+=@{bucket=$bucket.Name;name=$subject;reason='exact name in selected Scoop buckets'}
                }
            }
        }
        if(!$searchMatches.Count){
            foreach($bucket in $buckets){
                foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $bucket.FullName 'bucket') -File -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object BaseName)){
                    if($file.BaseName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$'){continue}
                    try{$manifest=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json}catch{continue}
                    $haystack=$file.BaseName+' '+[string](Property $manifest 'description')+' '+[string](Property $manifest 'homepage')
                    if($haystack.IndexOf($subject,[StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
                    $searchMatches+=@{bucket=$bucket.Name;name=$file.BaseName;reason='matched in selected Scoop buckets'}
                    if($searchMatches.Count -ge $searchLimit){break}
                }
                if($searchMatches.Count -ge $searchLimit){break}
            }
        }
        $rows=@()
        foreach($match in @($searchMatches|Select-Object -First $searchLimit)){
            $row=Scoop-Info $root $match.bucket $match.name;$row['matchReason']=$match.reason;$rows+=,$row
        }
        return @($rows)
}
