# Route through existing ks-cli when available; retain native zsetup integrity checks.
param([ValidateSet('Plan','Ensure')][string]$Action='Plan',
      [Parameter(Mandatory=$true)][string]$Destination,
      [string]$Core,[string]$ArchiveCache,[string]$ReleaseLock,[string]$KsCli,
      [ValidateSet('auto','direct','accelerated','race')][string]$DownloadMode='auto')
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$stage=$null
$published=@()
$exitCode=11
$download=$null
$downloader='zsetup'
$nativeExitCode=$null
function Emit($status,$extra) {
    $value=[ordered]@{schemaVersion=1;tool='mise';platform='windows';status=$status;
        version=$version;path=$Destination;serviceOperations=$false;exitCode=$exitCode}
    foreach($key in $extra.Keys){$value[$key]=$extra[$key]}
    [Console]::Out.WriteLine((ConvertTo-Json -InputObject $value -Depth 6 -Compress))
}
function Preserve-Reparse($path) {
    while($path){
        if(Test-Path -LiteralPath $path){
            if((Get-Item -Force -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){$script:exitCode=17;throw 'Preserve existing reparse paths'}
        }
        $parent=Split-Path -Parent $path
        if($parent -eq $path){break}
        $path=$parent
    }
}
try {
    if(-not$ReleaseLock){$ReleaseLock=Join-Path $PSScriptRoot '../references/tools.lock.json'}
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){$exitCode=18;throw 'Run on the native Windows target'}
    $arch=$env:PROCESSOR_ARCHITEW6432
    if(-not$arch){$arch=$env:PROCESSOR_ARCHITECTURE}
    if($arch -cne 'AMD64'){$exitCode=18;throw 'No locked artifact for this native Windows architecture'}
    if(-not$KsCli){$KsCli=$env:KAI_KSCLI_BIN}
    if(-not$KsCli){$command=Get-Command ks-cli.exe -ErrorAction SilentlyContinue;if($command){$KsCli=$command.Source}}
    $lock=Get-Content -LiteralPath $ReleaseLock -Raw|ConvertFrom-Json
    $version=[string]$lock.mise.version
    $artifact=$lock.mise.artifacts.'windows-x64'
    if($version -cnotmatch '^\d+\.\d+\.\d+$' -or $null -eq $artifact -or
       $artifact.url -cnotmatch '^https://[^\s]+$' -or $artifact.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
       $artifact.size -le 0 -or $artifact.size -gt 67108864){$exitCode=14;throw 'Invalid locked native mise artifact'}
    if(-not[IO.Path]::IsPathRooted($Destination) -or [IO.Path]::GetFileName($Destination) -cne 'mise.exe'){
        $exitCode=12;throw 'Choose an absolute destination ending in mise.exe'
    }
    $Destination=[IO.Path]::GetFullPath($Destination)
    $parent=Split-Path -Parent $Destination
    $receipt=Join-Path $parent 'mise.kai-bootstrap.json'
    $names=@('mise.exe','mise-shim.exe')
    Preserve-Reparse $Destination
    Preserve-Reparse $receipt
    Preserve-Reparse (Join-Path $parent 'mise-shim.exe')
    $existing=@($names|Where-Object{Test-Path -LiteralPath (Join-Path $parent $_)})
    if($existing.Count -or (Test-Path -LiteralPath $receipt)){
        $exitCode=17
        if($existing.Count -ne $names.Count -or -not(Test-Path -LiteralPath $receipt -PathType Leaf)){throw 'Preserve existing mise files without complete bootstrap ownership'}
        $owned=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json
        if($owned.owner -cne 'kai-mise-bootstrap-v1' -or $owned.version -cne $version -or $owned.archiveSha256 -cne $artifact.sha256){throw 'Preserve mise files from a different owner or release'}
        foreach($name in $names){
            $file=Join-Path $parent $name
            $record=$owned.files.$name
            if(-not(Test-Path -LiteralPath $file -PathType Leaf) -or $null -eq $record -or
               (Get-Item -LiteralPath $file).Length -ne $record.size -or
               (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.sha256){throw 'Preserve changed managed mise files; inspect their original owner'}
        }
        $exitCode=0;Emit 'reused' @{};exit 0
    }
    if($KsCli -and -not$ArchiveCache){
        if(-not(Test-Path -LiteralPath $KsCli -PathType Leaf)){$exitCode=127;throw 'The explicitly selected ks-cli is missing; preserve the selected downloader'}
        $downloader='ks-cli'
    }
    if($Action -eq 'Plan'){$exitCode=0;Emit 'missing' @{artifact=$artifact;architecture='x64';downloader=$downloader;downloadMode=$DownloadMode;serviceOperations=$false};exit 0}
    if(-not$Core -or -not(Test-Path -LiteralPath $Core -PathType Leaf)){throw 'Supply an existing trusted native zsetup executable'}
    $coreVersion=(& $Core --version|Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or $coreVersion -notmatch '^zsetup\s+(\d+\.\d+\.\d+)$' -or [version]$Matches[1] -lt [version]'0.4.0'){throw 'Native zsetup >=0.4.0 is required'}
    $drive=New-Object IO.DriveInfo([IO.Path]::GetPathRoot($Destination))
    if($drive.AvailableFreeSpace -lt 268435456){$exitCode=12;throw 'At least 256 MiB free staging space is required'}
    [IO.Directory]::CreateDirectory($parent)|Out-Null
    $stage=Join-Path $parent ('.mise-stage-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($stage)|Out-Null
    $archive=Join-Path $stage 'mise.zip'
    if($ArchiveCache){
        Preserve-Reparse $ArchiveCache
        if(-not(Test-Path -LiteralPath $ArchiveCache -PathType Leaf) -or (Get-Item -LiteralPath $ArchiveCache).Length -ne $artifact.size -or
           (Get-FileHash -LiteralPath $ArchiveCache -Algorithm SHA256).Hash.ToLowerInvariant() -cne $artifact.sha256){$exitCode=14;throw 'Explicit archive cache differs from the locked SHA256 or size'}
        [IO.File]::Copy($ArchiveCache,$archive,$false)
    } elseif($KsCli){
        $raw=(& $KsCli download --allow-start=false --mode=$DownloadMode --json --timeout=360s -O $archive $artifact.url|Out-String).Trim()
        $nativeExitCode=$LASTEXITCODE
        if($raw){[Console]::Error.WriteLine($raw)}
        if($nativeExitCode -ne 0){
            if($nativeExitCode -gt 0 -and $nativeExitCode -le 255){$exitCode=$nativeExitCode}
            throw ('ks-cli mise download failed with exit '+$nativeExitCode)
        }
        $result=$raw|ConvertFrom-Json
        if($result.status -cne 'ok' -or $result.mode -cne $DownloadMode -or -not$result.selected){throw 'ks-cli did not return a successful route receipt'}
        $download=@{status=$result.status;mode=$result.mode;strategy=$result.strategy;selected=$result.selected;bytes=$result.bytes;durationMs=$result.duration_ms;speedBps=$result.speed_bps}
        if(-not(Test-Path -LiteralPath $archive -PathType Leaf) -or
           (Get-Item -LiteralPath $archive).Length -ne $artifact.size -or
           (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $artifact.sha256){$exitCode=14;throw 'ks-cli downloaded content differs from the locked SHA256 or size'}
    }
    # An existing verified archive is reused by the canonical native downloader.
    # Its integrity checks remain active regardless of the transport choice.
    & $Core download -o $archive --sha256 $artifact.sha256 --size ([string]$artifact.size) `
        --overall-timeout 360s --probe-timeout 90s --connect-timeout 15s --read-idle-timeout 90s `
        $artifact.url | ForEach-Object{[Console]::Error.WriteLine($_)}
    if($LASTEXITCODE -ne 0){$exitCode=11;throw ('Native mise download failed with exit '+$LASTEXITCODE)}
    if((Get-Item -LiteralPath $archive).Length -ne $artifact.size -or
       (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $artifact.sha256){$exitCode=14;throw 'Downloaded mise archive differs from the lock'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    $files=[ordered]@{}
    try {
        foreach($name in $names){
            $entries=@($zip.Entries|Where-Object{$_.FullName -ceq ('mise/bin/'+$name)})
            if($entries.Count -ne 1 -or $entries[0].Length -lt 2 -or $entries[0].Length -gt 134217728){throw 'Native ZIP executable entry is missing, duplicated or too large'}
            $entry=$entries[0];$inputStream=$entry.Open();$output=$null;$file=Join-Path $stage $name
            try {
                $output=[IO.File]::Open($file,[IO.FileMode]::CreateNew)
                $buffer=New-Object byte[] 65536;$total=0
                while(($count=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0){
                    $total+=$count;if($total -gt $entry.Length){throw 'Native ZIP extraction exceeded its declared size'}
                    $output.Write($buffer,0,$count)
                }
                if($total -ne $entry.Length){throw 'Native ZIP extraction was truncated'}
            } finally {if($null -ne $output){$output.Dispose()};$inputStream.Dispose()}
            $header=[IO.File]::OpenRead($file)
            try{if($header.ReadByte() -ne 77 -or $header.ReadByte() -ne 90){throw 'Expected a native Windows executable'}}finally{$header.Dispose()}
            $files[$name]=@{size=(Get-Item -LiteralPath $file).Length;sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()}
        }
    } finally {$zip.Dispose()}
    $reported=(& (Join-Path $stage 'mise.exe') --version|Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or $reported -cnotmatch ('^'+[regex]::Escape($version)+'(?:\s|$)')){throw 'Extracted native mise version differs from the lock'}
    $owned=@{schemaVersion=1;owner='kai-mise-bootstrap-v1';version=$version;archiveSha256=$artifact.sha256;files=$files}
    $receiptStage=Join-Path $stage 'mise.kai-bootstrap.json'
    [IO.File]::WriteAllText($receiptStage,($owned|ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    foreach($name in @($names)+@('mise.kai-bootstrap.json')){
        $target=Join-Path $parent $name
        [IO.File]::Move((Join-Path $stage $name),$target)
        $published+=@{path=$target;sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    $exitCode=0;Emit 'installed' @{archiveSha256=$artifact.sha256;files=$files;downloader=$downloader;download=$download;archiveCacheUsed=[bool]$ArchiveCache};exit 0
} catch {
    foreach($file in $published){
        if((Test-Path -LiteralPath $file.path -PathType Leaf) -and
           (Get-FileHash -LiteralPath $file.path -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $file.sha256){Remove-Item -LiteralPath $file.path -Force}
    }
    Emit 'failed' @{reason=$_.Exception.Message;downloader=$downloader;download=$download;nativeExitCode=$nativeExitCode};exit $exitCode
} finally {
    if($stage -and (Test-Path -LiteralPath $stage)){Remove-Item -LiteralPath $stage -Recurse -Force}
}
