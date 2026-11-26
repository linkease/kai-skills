# Same bounded software-query/v1 facts as the Unix entry; not an Agent tool API.
function Query-Text($value) {
    if($null -eq $value){return $null}
    $text=[string]$value
    # Enumerate Unicode scalars without cutting a surrogate pair.
    $length=0;$end=0
    while($end -lt $text.Length -and $length -lt 239){if([char]::IsHighSurrogate($text[$end]) -and $end+1 -lt $text.Length){$end++};$end++;$length++}
    if($end -lt $text.Length-1){return $text.Substring(0,$end)+[char]0x2026}
    return $text
}
function Query-Emit($rows,[string]$status='success',[string]$reason='') {
    $items=@();$ordered=@($rows|Sort-Object @{Expression={if($_.id -ieq $query -or $_.name -ieq $query){0}else{1}}},id)
    foreach($row in @($ordered|Select-Object -First $limit)) {
        if(!$row.id -or ([string]$row.id).Length -gt 256){throw 'invalid-provider-identity'}
        $item=[ordered]@{}
        foreach($key in @('id','name','description','source','kind','installed','installedVersion','availableVersion','candidateVersion','runtimeVersion','scope','compatibility','matchReason')) {
            $property=$row.PSObject.Properties[$key]
            if($null -eq $property -or $null -eq $property.Value){continue}
            $value=$property.Value;if($key -in @('name','description','matchReason')){$value=Query-Text $value}
            $item[$key]=$value
        }
        $items+=,$item
    }
    $result=[ordered]@{protocol='software-query/v1';schemaVersion=1;targetId=$target;action=$Operation;status=$status;readOnly=$true;untrustedData=$true;observedAt=[DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ');truncated=(@($items|Where-Object { $_.name -like ('*'+[char]0x2026) -or $_.description -like ('*'+[char]0x2026) -or $_.matchReason -like ('*'+[char]0x2026) }).Count -gt 0);items=@($items);limit=$limit;hasMore=($ordered.Count -gt $limit);reason=$reason;effects=@()}
    $json=$result|ConvertTo-Json -Depth 12 -Compress
    if([Text.Encoding]::UTF8.GetByteCount($json)+[Text.Encoding]::UTF8.GetByteCount([Environment]::NewLine) -gt 8192){throw 'query-result-too-large'}
    [Console]::WriteLine($json)
}
