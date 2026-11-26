[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$TargetId,
    [string[]]$Sections = @('os','tools'),
    [ValidateRange(1,30)][int]$DeadlineSeconds = 5,
    [string]$EngineContext = ''
)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$now = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$facts = [ordered]@{}
$evidence = New-Object System.Collections.ArrayList
$errors = New-Object System.Collections.ArrayList
$operationStatus = 'succeeded'
$clock = [Diagnostics.Stopwatch]::StartNew()

function Add-Fact([string]$Name, $Value, [string]$Source, [string]$Status='observed') {
    $script:facts[$Name] = $Value
    [void]$script:evidence.Add([ordered]@{
        id = 'fact-' + ($script:evidence.Count+1); source = $Source; status = $Status
        observedAt = $script:now; factPaths = @('/facts/'+$Name)
    })
}
function Add-Error([string]$Code,[string]$Message) {
    [void]$script:errors.Add(@{code=$Code;message=$Message})
    if ($script:operationStatus -ne 'failed') { $script:operationStatus='partial' }
}
function Find-Programs([string[]]$Names) {
    $records = New-Object System.Collections.ArrayList
    foreach ($name in $Names) {
        foreach ($command in @(Get-Command -Name $name -All -ErrorAction SilentlyContinue)) {
            if ($null -eq $command) { continue }
            $record = [ordered]@{ name=$name;commandType=[string]$command.CommandType }
            if ($command.CommandType -eq 'Application' -or $command.CommandType -eq 'ExternalScript') {
                $record['path'] = [string]$command.Source
            } elseif ($command.CommandType -eq 'Alias') {
                # Alias targets are command identities, never executable content.
                $record['aliasTarget'] = [string]$command.ResolvedCommandName
            }
            [void]$records.Add($record)
        }
    }
    return ,$records.ToArray()
}
function Quote-NativeArgument([string]$Value) {
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    # CommandLineToArgvW quoting; this is not evaluated as PowerShell code.
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"'+$escaped+'"'
}
function Invoke-Probe([string]$Executable,[string[]]$Arguments) {
    $remaining = [int][Math]::Floor(($DeadlineSeconds*1000-$script:clock.ElapsedMilliseconds))
    if ($remaining -le 0) { return @{code=124;output='';error=''} }
    $remaining = [Math]::Min(2000,$remaining)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$Executable
    $info.Arguments=($Arguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' '
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.StandardOutputEncoding=$script:utf8;$info.StandardErrorEncoding=$script:utf8
    $process=New-Object Diagnostics.Process;$process.StartInfo=$info
    try {
        [void]$process.Start()
        $outTask=$process.StandardOutput.ReadToEndAsync();$errTask=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($remaining)) {
            # Terminate only this query process tree. Never stop Docker services.
            & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F 2>$null | Out-Null
            if (-not $process.HasExited) { $process.Kill() }
            return @{code=124;output='';error=''}
        }
        $out=$outTask.GetAwaiter().GetResult();$err=$errTask.GetAwaiter().GetResult()
        if ($out.Length -gt 4096 -or $err.Length -gt 4096) { return @{code=126;output='';error=''} }
        return @{code=$process.ExitCode;output=$out.TrimEnd();error=$err}
    } catch { return @{code=127;output='';error=''} }
    finally { $process.Dispose() }
}

$selected = @($Sections | ForEach-Object { $_.Split(',') })
if ($TargetId.Length -gt 200 -or @($selected | Where-Object { $_ -notin @('os','tools','docker') }).Count -gt 0) {
    $operationStatus='failed'; Add-Error 'INVALID_ARGUMENT' 'Select a valid target ID and explicit query sections.'
} elseif ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    $operationStatus='failed'; Add-Error 'UNSUPPORTED_PLATFORM' 'This entry uses native Windows facilities; use inspect.sh on Unix.'
} else {
    if ($selected -contains 'os') {
        # Registry reads do not invoke an installer, service or shell profile.
        try {
            $version=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
            Add-Fact 'os' ([ordered]@{
                family='windows'; distribution='windows'; name=[string]$version.ProductName
                version=[Environment]::OSVersion.Version.ToString();build=[string]$version.CurrentBuildNumber
            }) 'Windows registry and current native operating-system version'
        } catch {
            Add-Fact 'os' $null 'Windows registry query' 'denied'
            Add-Error 'OS_FACTS_UNAVAILABLE' 'The Windows version facts could not be read.'
        }
        Add-Fact 'architecture' ([string]$env:PROCESSOR_ARCHITECTURE) 'native process architecture environment'
        Add-Fact 'serviceManager' 'windows-scm' 'native Windows service control platform'
        Add-Fact 'environment' ([ordered]@{process64Bit=[Environment]::Is64BitProcess;os64Bit=[Environment]::Is64BitOperatingSystem;hostDistribution=$null}) 'native process and OS bitness; outer host not inferred'
    }
    if ($selected -contains 'tools') {
        Add-Fact 'packageManagers' (Find-Programs @('winget','scoop','choco','brew','apt','apk','opkg','yum','dnf')) 'Get-Command -All; command presence does not establish install privileges'
        Add-Fact 'downloadTools' (Find-Programs @('wget','curl','Invoke-WebRequest')) 'Get-Command -All; wget aliases and download tools are not package managers'
        Add-Fact 'containerClients' (Find-Programs @('docker','podman','nerdctl')) 'Get-Command -All; clients do not establish engine availability'
    }
    if ($selected -contains 'docker') {
        $docker=@(Get-Command docker -CommandType Application -ErrorAction SilentlyContinue)
        if ($docker.Count -eq 0) {
            Add-Fact 'dockerClientAvailable' $false 'Get-Command docker -CommandType Application' 'absent'
        } else {
            Add-Fact 'dockerClientAvailable' $true 'Get-Command docker -CommandType Application'
            $exe=$docker[0].Source
            $context=Invoke-Probe $exe @('context','show')
            if ($context.code -ne 0) {
                Add-Fact 'dockerContext' $null 'docker context show' 'unknown'
                Add-Error 'DOCKER_CONTEXT_UNAVAILABLE' 'The Docker context probe did not complete.'
            } else {
                $contextName=$context.output
                if ($EngineContext) { $contextName=$EngineContext }
                Add-Fact 'dockerContext' $contextName 'docker context show or explicitly selected existing context'
                $endpoint=Invoke-Probe $exe @('context','inspect',$contextName,'--format','{{.Endpoints.docker.Host}}')
                if ($endpoint.code -ne 0) {
                    Add-Fact 'dockerEndpoint' $null 'docker context inspect' 'unknown'
                    Add-Error 'DOCKER_ENDPOINT_UNAVAILABLE' 'The selected endpoint could not be read.'
                } else {
                    $address=$endpoint.output
                    if (-not $EngineContext -and -not $env:DOCKER_CONTEXT -and $env:DOCKER_HOST) { $address=$env:DOCKER_HOST }
                    $public=[regex]::Replace($address,'://[^ /]*@','://[redacted]@')
                    $public=[regex]::Replace($public,'\?.*$','?[redacted]')
                    Add-Fact 'dockerEndpoint' $public 'selected Docker context and applicable DOCKER_HOST override; userinfo redacted'
                    $local=$address -match '^(npipe://|unix://|tcp://127\.0\.0\.1:|tcp://localhost:)'
                    if (-not $local -and -not $EngineContext) {
                        Add-Fact 'dockerApiReachable' $null 'remote endpoint not selected for probing' 'unknown'
                    } else {
                        $argv=@('version','--format','{{.Server.Version}}')
                        if ($EngineContext) { $argv=@('--context',$EngineContext)+$argv }
                        $server=Invoke-Probe $exe $argv
                        if ($server.code -eq 0 -and $server.output) {
                            Add-Fact 'dockerApiReachable' $true 'Docker version API at selected endpoint'
                            Add-Fact 'dockerServerVersion' $server.output 'Docker version API'
                        } elseif ($server.code -eq 124) {
                            Add-Fact 'dockerApiReachable' $null 'Docker API probe deadline' 'timeout'
                            Add-Error 'DOCKER_TIMEOUT' 'The engine probe reached its deadline.'
                        } elseif ($server.code -eq 126) {
                            Add-Fact 'dockerApiReachable' $null 'Docker response byte limit' 'unknown'
                            Add-Error 'PROBE_OUTPUT_LIMIT' 'The external response exceeded the probe byte limit; no truncated version was accepted.'
                        } elseif ($server.error -match '(?i)permission denied|access.*denied') {
                            Add-Fact 'dockerApiReachable' $null 'Docker API permission check' 'denied'
                            Add-Error 'DOCKER_ACCESS_DENIED' 'The current identity cannot access the selected engine.'
                        } elseif ($server.error -match '(?i)cannot connect|connection refused|cannot find the file') {
                            Add-Fact 'dockerApiReachable' $false 'Docker API connection attempt failed'
                        } else {
                            Add-Fact 'dockerApiReachable' $null 'Docker API probe without a confirmed verdict' 'unknown'
                            Add-Error 'DOCKER_PROBE_FAILED' 'The engine response could not establish availability.'
                        }
                    }
                }
            }
        }
    }
}
$result=[ordered]@{
    schemaVersion=1;operation='system.inspect';operationStatus=$operationStatus;targetId=$TargetId
    readOnly=$true;observedAt=$now;facts=$facts;evidence=@($evidence.ToArray())
    effects=@{requested=@();completed=@();unknown=@();remaining=@()}
    verification=@{status='not_required';checks=@()};errors=@($errors.ToArray());truncated=$false
}
$json=$result | ConvertTo-Json -Depth 24 -Compress
if ($utf8.GetByteCount($json) -gt 8192) {
    $result.operationStatus='failed';$result.facts=@{};$result.evidence=@()
    $result.errors=@(@{code='RESULT_LIMIT';message='Selected facts exceed the default byte limit; query fewer sections.'})
    $json=$result | ConvertTo-Json -Depth 24 -Compress
}
[Console]::WriteLine($json)
if ($result.operationStatus -ne 'succeeded') { exit 1 }
