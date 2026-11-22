# Scoop commands may call exit. Isolate them in an owned native child process.
function Task-ScoopProcess([object[]]$Arguments) {
    $ErrorActionPreference='Continue'
    $output=@(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass @Arguments 2>$null)
    return @{output=$output;exitCode=$LASTEXITCODE}
}
function Task-QueryScoop($r) {
    $name=[string]$r.software
    $installed='';$candidate='';$comparison='unknown'
    $source=@{id='scoop';freshness='cache-unverified';fetchedAt=$null}
    $root=$env:KAI_SCOOP_ROOT
    if(!$root){$root=$env:SCOOP}
    if(!$root){
        $config=Join-Path $env:USERPROFILE '.config/scoop/config.json'
        if(Test-Path -LiteralPath $config -PathType Leaf){$root=[string](Get-Content -LiteralPath $config -Raw|ConvertFrom-Json).root_path}
    }
    if(!$root){$root=Join-Path $env:USERPROFILE 'scoop'}
    $native=Join-Path $root 'apps/scoop/current/bin/scoop.ps1'
    if(!(Test-Path -LiteralPath $native -PathType Leaf)){throw 'scoop-unavailable'}
    $safe=$native.Replace("'","''")
    $expression="& '$safe' info '$name' | ConvertTo-Json -Depth 5 -Compress"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($expression))
    $result=Task-ScoopProcess -Arguments @('-EncodedCommand',$encoded)
    $info=@(($result.output -join "`n")|ConvertFrom-Json)
    if($result.exitCode -ne 0 -or $info.Count -ne 1 -or [string]$info[0].Name -cne $name){throw 'no-unique-native-candidate'}
    $info=$info[0];$candidate=[string]$info.Version
    $bucket=[string]$info.Source
    if($bucket -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$'){throw 'unconfirmed-scoop-source'}
    if($info.Installed){
        # A single native registration is sufficient for package facts. It does
        # not establish functional health or require Scoop's current junction.
        $records=@(([string]$info.Installed -split "`n")|Where-Object { $_.Trim() })
        if($records.Count -eq 1 -and $records[0].Trim() -match '^([A-Za-z0-9][A-Za-z0-9._+:~-]{0,127})( \*global\*)?$'){
            $installed=$Matches[1]
        } else {
            # Several retained registrations require a proven selected path.
            $result=Task-ScoopProcess -Arguments @('-File',$native,'prefix',$name)
            $prefix=@($result.output)
            if($result.exitCode -ne 0 -or $prefix.Count -ne 1 -or ![IO.Path]::IsPathRooted([string]$prefix[0])){throw 'unconfirmed-scoop-prefix'}
            $current=Join-Path ([string]$prefix[0]) 'scoop-manifest.json'
            if(!(Test-Path -LiteralPath $current)){ $current=Join-Path ([string]$prefix[0]) 'manifest.json' }
            if(!(Test-Path -LiteralPath $current -PathType Leaf)){throw 'installed-scoop-manifest-missing'}
            $installed=[string](Get-Content -LiteralPath $current -Raw|ConvertFrom-Json).version
            if(!$installed){throw 'installed-scoop-version-missing'}
        }
    }
    if($installed -and $candidate -and $installed -notlike 'nightly*' -and $candidate -notlike 'nightly*'){
        . (Join-Path $root 'apps/scoop/current/lib/versions.ps1')
        $order=Compare-Version -ReferenceVersion $installed -DifferenceVersion $candidate
        $comparison=switch($order){0{'same'};1{'candidate-newer'};-1{'installed-newer'};default{'unknown'}}
    }
    $source.id="scoop:$bucket"
    $fetch=Join-Path $root "buckets/$bucket/.git/FETCH_HEAD"
    if(Test-Path -LiteralPath $fetch -PathType Leaf){$source.fetchedAt=(Get-Item -LiteralPath $fetch).LastWriteTimeUtc.ToString('o')}
    return @{manager='scoop';installedVersion=$installed;candidateVersion=$candidate;comparison=$comparison;source=$source;providerRoot=$root;nativeId="$bucket/$name";functionalValidation='not-run'}
}
