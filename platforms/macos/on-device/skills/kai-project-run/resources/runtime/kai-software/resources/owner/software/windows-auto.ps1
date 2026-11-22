# Existing native registration wins. Discovery never installs a provider and
# does not switch an explicitly selected source.
function Task-QueryAutomaticWindows($r) {
    $rows=@();$unavailable=@()
    foreach($provider in @('scoop','winget')){
        try {
            $row=if($provider -eq 'scoop'){Task-QueryScoop $r}else{Task-QueryWinGet $r}
            if($row.installedVersion){
                $row['selectionBasis']='existing-native-registration'
                return $row
            }
            $rows+=,$row
        } catch {$unavailable+=$provider}
    }
    if($rows.Count -eq 1){$rows[0]['selectionBasis']='single-available-provider';return $rows[0]}
    if($rows.Count -gt 1){return @{reason='native-provider-required';stage='windows-source-selection';choices=$rows}}
    return @{reason='native-provider-query-unavailable';stage='windows-discovery';unavailableProviders=$unavailable}
}
