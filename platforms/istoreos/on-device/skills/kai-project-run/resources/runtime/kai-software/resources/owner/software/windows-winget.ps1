function Task-QueryWinGet($r) {
    $name=[string]$r.software
    $installed='';$candidate='';$comparison='unknown'
    $source=@{id='winget';freshness='provider-managed-cache';fetchedAt=$null}
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
    $catalog=@(Find-WinGetPackage -Id $name -MatchOption Equals -Source winget -Count 2 -ErrorAction Stop)
    $local=@(Get-WinGetPackage -Id $name -MatchOption Equals -Source winget -Count 2 -ErrorAction Stop)
    if($catalog.Count -ne 1 -or $catalog[0].Id -cne $name -or $catalog[0].Source -ne 'winget' -or $local.Count -gt 1){throw 'no-unique-native-candidate'}
    $candidate=[string]$catalog[0].Version
    if(!$candidate){throw 'incomplete-native-catalog'}
    if($local.Count -eq 1){
        if($local[0].Id -cne $name -or $local[0].Source -ne 'winget'){throw 'native-source-conflict'}
        $installed=[string]$local[0].InstalledVersion
        if($installed -ceq $candidate){$comparison='same'}
        elseif($local[0].IsUpdateAvailable -eq $true){$comparison='candidate-newer'}
    }
    return @{manager='winget';installedVersion=$installed;candidateVersion=$candidate;comparison=$comparison;source=$source;nativeId=$name;functionalValidation='not-run'}
}
