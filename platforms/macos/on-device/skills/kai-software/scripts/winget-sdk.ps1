# Official SDK worker: a fresh PowerShell 7.5+ MTA process owns all proxy state.
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
function Emit($value){[Console]::Out.WriteLine((ConvertTo-Json -InputObject $value -Depth 8 -Compress))}
function Fail([int]$code,[string]$category,[string]$reason){Emit @{schemaVersion=1;status='failed';category=$category;reason=$reason;exitCode=$code};exit $code}
try {
 $request=[Console]::In.ReadToEnd()|ConvertFrom-Json
 if($request.action -notin @('info','search')){Fail 18 'unsupported-accelerated-operation' 'This SDK candidate validates accelerated search/info; mutations require their own native validation.'}
 $id=[string]$request.subject
 if(-not$id -or $id.Length -gt 512 -or $id.StartsWith('-')){Fail 2 'usage' 'Supply a bounded literal software subject.'}
 if($request.action -eq 'info' -and $id -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$'){Fail 2 'usage' 'Use an exact source-qualified package identifier.'}
 if($PSVersionTable.PSVersion -lt [version]'7.5' -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'MTA'){Fail 18 'native-adapter-unavailable' 'The SDK worker requires PowerShell 7.5+ and -MTA.'}
 $sdk=$env:KAI_WINGET_SDK_DIR
 if(-not$sdk -or -not[IO.Path]::IsPathFullyQualified($sdk)){Fail 18 'native-adapter-unavailable' 'Prepare an explicit KAI_WINGET_SDK_DIR with the pinned official SDK.'}
 $lock=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../resources/winget-sdk.lock.json') -Raw|ConvertFrom-Json
 if([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString() -cne $lock.architecture){Fail 18 'unsupported-sdk-architecture' 'The SDK lock is not validated for this worker architecture.'}
 foreach($file in $lock.files.PSObject.Properties){
  $path=Join-Path $sdk $file.Name
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Fail 18 'native-adapter-unavailable' 'A pinned official SDK file is missing.'}
  $item=Get-Item -LiteralPath $path
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -ne $file.Value.size -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.Value.sha256){Fail 11 'sdk-integrity-failed' 'An official SDK file differs from its reviewed source lock.'}
 }
 $proxy=$null
 if(-not[Uri]::TryCreate($env:KSPEEDER_WINGET_PROXY,[UriKind]::Absolute,[ref]$proxy) -or $proxy.Scheme -ne 'http' -or $proxy.Host -ne '127.0.0.1' -or $proxy.Port -lt 1 -or $proxy.UserInfo){Fail 11 'acceleration-unavailable' 'Start the SDK worker through ks-cli winget exec.'}
 Add-Type -Path (Join-Path $PSScriptRoot '../resources/winget-wininet.cs')
 if(-not[KaiWinGetProcess]::SetDllDirectory($sdk)){Fail 11 'native-adapter-unavailable' 'Could not select the verified SDK native directory.'}
 [KaiWinGetProcess]::Proxy($proxy.Authority)
 foreach($name in @('WinRT.Runtime.dll','Microsoft.Windows.SDK.NET.dll','Microsoft.Management.Deployment.CsWinRTProjection.dll')){Add-Type -Path (Join-Path $sdk $name)}
 $manager=[Microsoft.Management.Deployment.PackageManager]::new()
 $reference=$manager.GetPackageCatalogByName('winget')
 if($null -eq $reference -or $reference.Info.Name -cne 'winget' -or ([string]$reference.Info.Argument).TrimEnd('/') -cne 'https://cdn.winget.microsoft.com/cache'){Fail 4 'source-mismatch' 'The registered catalog is not the official winget source.'}
 $composite=[Microsoft.Management.Deployment.CreateCompositePackageCatalogOptions]::new()
 $composite.Catalogs.Add($reference)
 $composite.CompositeSearchBehavior=[Microsoft.Management.Deployment.CompositeSearchBehavior]::RemotePackagesFromAllCatalogs
 $connection=$manager.CreateCompositePackageCatalog($composite).Connect()
 if($connection.Status.ToString() -ne 'Ok'){Fail 11 'catalog-unavailable' 'The official catalog could not connect through the selected proxy.'}
 $options=[Microsoft.Management.Deployment.FindPackagesOptions]::new()
 $filter=[Microsoft.Management.Deployment.PackageMatchFilter]::new();$filter.Value=$id
 if($request.action -eq 'info'){
  $filter.Field=[Microsoft.Management.Deployment.PackageMatchField]::Id;$filter.Option=[Microsoft.Management.Deployment.PackageFieldMatchOption]::Equals
  $options.Filters.Add($filter);$options.ResultLimit=2
 }else{
  $filter.Field=[Microsoft.Management.Deployment.PackageMatchField]::CatalogDefault;$filter.Option=[Microsoft.Management.Deployment.PackageFieldMatchOption]::ContainsCaseInsensitive
  $options.Selectors.Add($filter);$options.ResultLimit=3
 }
 $found=$connection.PackageCatalog.FindPackages($options)
 if($found.Status.ToString() -ne 'Ok'){Fail 11 'catalog-unavailable' 'The official native catalog search failed.'}
 if($request.action -eq 'info' -and ($found.Matches.Count -ne 1 -or $found.Matches[0].CatalogPackage.Id -cne $id)){Fail 4 'no-unique-candidate' 'The native source did not return one exact matching ID.'}
 $rows=@()
 foreach($match in $found.Matches){
  $package=$match.CatalogPackage;$versions=@($package.AvailableVersions);$default=$package.DefaultInstallVersion
  if($versions.Count -eq 0 -or $null -eq $default){Fail 11 'catalog-unavailable' 'Native version data is unavailable.'}
  if($default.PackageCatalog.Info.Name -cne 'winget' -or $default.Id -cne $package.Id){Fail 4 'source-mismatch' 'The actual package version belongs to a different catalog.'}
  $available=@($versions|ForEach-Object{$_.Version})
  if(@($available|Where-Object{[string]::IsNullOrWhiteSpace($_)}).Count -gt 0 -or $available -cnotcontains $default.Version){Fail 11 'catalog-unavailable' 'The native catalog returned incomplete version data.'}
  $installed='';if($null -ne $package.InstalledVersion){$installed=[string]$package.InstalledVersion.Version}
  $row=[ordered]@{schemaVersion=1;id=('winget:'+$package.Id);name=$package.Id;displayName=$package.Name;type='system-package';source=$default.PackageCatalog.Info.Name;manager='winget';platform='windows';compatible=$true;availableVersion=$default.Version;availableVersions=$available;installedVersion=$installed;installed=($installed -ne '');entrypoint='';evidenceTime=[DateTime]::UtcNow.ToString('o');nextStep='Use the registered native application entry.';acceleration=@{transport='kspeeder-connect';systemProxyChanged=$false;originTls='preserved'}}
  if($request.action -eq 'search'){$row['matchReason']='matched in the selected official native catalog'}
  $rows+=$row
 }
 if($request.action -eq 'info'){Emit $rows[0]}else{Emit @($rows)}
 exit 0
}catch{
 Emit @{schemaVersion=1;status='failed';category='native-provider-error';reason='The official WinGet SDK operation failed; inspect the native log and HRESULT.';nativeResult=@{type=$_.Exception.GetType().FullName;hresult=$_.Exception.HResult};exitCode=11};exit 11
}
