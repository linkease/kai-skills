# Prepare locked SDK libraries only. Native zsetup remains the sole downloader.
param([ValidateSet('Plan','Ensure')][string]$Action='Plan',
      [Parameter(Mandatory=$true)][string]$Destination,[string]$Core,[string]$PackageCache)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$stage=$null
function Emit($value){[Console]::Out.WriteLine((ConvertTo-Json -InputObject $value -Depth 6 -Compress))}
try {
 $lock=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../kai-software/resources/winget-sdk.lock.json') -Raw|ConvertFrom-Json
 $files=@($lock.files.PSObject.Properties)
 if($Action -eq 'Plan'){
  Emit @{schemaVersion=1;action='plan';platform=$lock.platform;architecture=$lock.architecture;minimumPowerShell=$lock.minimumPowerShell;fileCount=$files.Count;packageCount=@($lock.packages).Count;destination=$Destination;systemInstallation=$false;packages=$lock.packages}
  exit 0
 }
 if(-not[IO.Path]::IsPathRooted($Destination) -or [IO.Path]::GetPathRoot($Destination).TrimEnd('\','/') -eq $Destination.TrimEnd('\','/')){throw 'Choose an absolute SDK subdirectory'}
 $parent=Split-Path -Parent $Destination
 $cursor=$parent
 while($cursor){if(Test-Path -LiteralPath $cursor){if((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Preserve reparse paths'}};$next=Split-Path -Parent $cursor;if($next -eq $cursor){break};$cursor=$next}
 if(Test-Path -LiteralPath $Destination){
  if((Get-Item -LiteralPath $Destination).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Preserve reparse destinations'}
  foreach($file in $files){$p=Join-Path $Destination $file.Name;if(-not(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-Item -LiteralPath $p).Length -ne $file.Value.size -or (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.Value.sha256){throw 'Preserve existing SDK directory: it does not match the lock'}}
  Emit @{schemaVersion=1;status='reused';path=$Destination;fileCount=$files.Count};exit 0
 }
 if(-not$Core -or -not(Test-Path -LiteralPath $Core -PathType Leaf)){throw 'Supply -Core with an existing trusted native zsetup executable'}
 $version=(& $Core --version|Out-String).Trim()
 if($LASTEXITCODE -ne 0 -or $version -notmatch '^zsetup\s+(\d+\.\d+\.\d+)' -or [version]$Matches[1] -lt [version]'0.4.0'){throw 'Native zsetup >=0.4.0 is required'}
 [IO.Directory]::CreateDirectory($parent)|Out-Null
 $stage=$Destination+'.stage-'+[Guid]::NewGuid().ToString('N');[IO.Directory]::CreateDirectory($stage)|Out-Null
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $index=0
 foreach($package in $lock.packages){
  if(-not$package.url.StartsWith('https://')){throw 'The SDK lock must use HTTPS'}
  $archive=Join-Path $stage ('package-'+$index+'.nupkg');$index++
  if($PackageCache){
   $cached=Join-Path $PackageCache ($package.id+'.'+$package.version+'.nupkg')
   if(-not(Test-Path -LiteralPath $cached -PathType Leaf) -or ((Get-Item -LiteralPath $cached).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'The explicit package cache is incomplete or contains a reparse file'}
   Copy-Item -LiteralPath $cached -Destination $archive
  }
  & $Core download -o $archive --sha256 $package.sha256 --size ([string]$package.size) $package.url | ForEach-Object {[Console]::Error.WriteLine($_)}
  if($LASTEXITCODE -ne 0){throw ('Native SDK download failed with exit '+$LASTEXITCODE)}
  $zip=[IO.Compression.ZipFile]::OpenRead($archive)
  try{
   foreach($file in $files|Where-Object{$_.Value.package -ceq $package.id}){
    $entry=$zip.GetEntry($file.Value.entry)
    if($null -eq $entry -or $entry.Length -ne $file.Value.size){throw 'SDK package entry size differs from the lock'}
    $output=Join-Path $stage $file.Name;$entryStream=$entry.Open();$stream=$null
    try{$stream=[IO.File]::Create($output);$buffer=New-Object byte[] 65536;$total=0;while(($count=$entryStream.Read($buffer,0,$buffer.Length)) -gt 0){$total+=$count;if($total -gt $file.Value.size){throw 'SDK extraction exceeded the locked size'};$stream.Write($buffer,0,$count)}}finally{if($null -ne $stream){$stream.Dispose()};$entryStream.Dispose()}
    if((Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.Value.sha256){throw 'Extracted SDK file digest differs from the lock'}
   }
  }finally{$zip.Dispose()}
  Remove-Item -LiteralPath $archive
 }
 [IO.Directory]::Move($stage,$Destination);$stage=$null
 Emit @{schemaVersion=1;status='prepared';path=$Destination;fileCount=$files.Count;systemInstallation=$false}
 exit 0
}catch{
 Emit @{schemaVersion=1;status='failed';category='sdk-preparation-failed';reason=$_.Exception.Message;exitCode=11};exit 11
}finally{
 if($stage -and (Test-Path -LiteralPath $stage)){Remove-Item -LiteralPath $stage -Recurse -Force}
}
