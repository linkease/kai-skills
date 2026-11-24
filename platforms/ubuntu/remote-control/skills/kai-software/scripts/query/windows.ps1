function Query-Windows {
    $providers=@($provider)
    if(!$provider){if($query -match '^(scoop|winget):'){$providers=@($Matches[1])}elseif($Operation -eq 'search'){$providers=@('scoop','winget')}else{throw 'source-qualified-id-required'}}
    $rows=@()
    foreach($source in $providers){
        if($source -notin @('scoop','winget')){throw 'unsupported-provider'}
        $subject=$query
        if($Operation -ne 'search'){
            if(!$query.StartsWith($source+':',[StringComparison]::Ordinal)){throw 'source-qualified-id-required'}
            $subject=$query.Substring($source.Length+1)
        }
        $action=if($Operation -eq 'search'){'search'}else{'info'}
        $payload=@{action=$action;subject=$subject;policy='none';searchLimit=($limit+1)}|ConvertTo-Json -Compress
        $entry=Join-Path $script:QueryScriptsRoot ($source+'.ps1')
        $raw=$payload|& $native -NoProfile -NonInteractive -File $entry 2>$privateLog
        if($LASTEXITCODE -ne 0){throw 'provider-query-failed'}
        $value=($raw|Out-String)|ConvertFrom-Json
        foreach($row in @($value)){
            $row|Add-Member -NotePropertyName kind -NotePropertyValue $row.type -Force
            $rows+=,$row
        }
    }
    Query-Emit $rows
}
