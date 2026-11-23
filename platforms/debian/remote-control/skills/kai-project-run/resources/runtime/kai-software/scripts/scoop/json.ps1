function Emit($Value) {
    [Console]::Out.WriteLine((ConvertTo-Json -InputObject $Value -Depth 12 -Compress))
}

function Json-Objects([string]$Text) {
    $results = @(); $start = -1; $depth = 0; $quoted = $false; $escaped = $false
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        if ($start -lt 0) {
            if ($character -eq '{') { $start = $index; $depth = 1; $quoted = $false; $escaped = $false }
            continue
        }
        if ($quoted) {
            if ($escaped) { $escaped = $false; continue }
            if ($character -eq '\') { $escaped = $true; continue }
            if ($character -eq '"') { $quoted = $false }
            continue
        }
        if ($character -eq '"') { $quoted = $true; continue }
        if ($character -eq '{') { $depth++ }
        if ($character -eq '}') {
            $depth--
            if ($depth -eq 0) {
                try { $results += $Text.Substring($start, $index - $start + 1) | ConvertFrom-Json } catch {}
                $start = -1
            }
        }
    }
    return @($results)
}

function Fail([int]$Code, [string]$Category, [string]$Reason, $NativeResult = $null) {
    Emit ([ordered]@{schemaVersion=1;status='failed';category=$Category;reason=$Reason;
        nativeResult=$NativeResult;exitCode=$Code})
    exit $Code
}

function Property($Value, [string]$Name) {
    if ($null -eq $Value) { return $null }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Effective($Manifest, [string]$Name, [string]$Architecture = $script:architecture) {
    $architectures = Property $Manifest 'architecture'
    $branch = Property $architectures $Architecture
    $value = Property $branch $Name
    if ($null -eq $value) { $value = Property $Manifest $Name }
    return $value
}

function Assert-Leaf([string]$Path, [string]$Label) {
    if (!$Path -or ![IO.Path]::IsPathRooted($Path)) { Fail 2 'usage' "$Label must be an absolute path." }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item -or $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Fail 127 'missing-executable' "$Label must be an existing regular file."
    }
}

function Invoke-NativeCaptured([string]$Executable, [object[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines=New-Object 'Collections.Generic.List[object]'
        & $Executable @Arguments 2>&1 | ForEach-Object {
            $line=[string]$_
            if($line.StartsWith('KAI_MARKET_STAGE:')){[Console]::Error.WriteLine($line)}else{
                $lines.Add($_)
                if($env:KSCLI_SCOOP_EVENTS -eq '1'){[Console]::Error.WriteLine('KAI_MARKET_LOG:'+$line)}
            }
        }
        $output=@($lines.ToArray())
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    return [pscustomobject]@{exitCode=$code;output=@($output)}
}
