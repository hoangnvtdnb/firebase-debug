param(
    [switch]$LiveViewer,  # giữ tương thích; viewer HTTP luôn bật
    [switch]$NoLiveViewer,
    [switch]$Fresh,       # xóa stream cũ, bắt đầu session mới
    [int]$ViewerPort = 8765,
    [switch]$NoBrowser
)
$OutputFile = "fa_logging_results_adb.html"
$StreamFile = "fa_logging_stream.jsonl"
$script:OutputFilePath = Join-Path $PSScriptRoot $OutputFile
$script:StreamFilePath = Join-Path $PSScriptRoot $StreamFile
$IncludeFile = "include_event.txt"
$ExcludeFile = "exclude_event.txt"
$IncludePropertyFile = "include_property.txt"
$ExcludePropertyFile = "exclude_property.txt"
$IncludeEventParamFile = "include_event_param.txt"
$ExcludeEventParamFile = "exclude_event_param.txt"
$ViewerIndex = (Resolve-Path (Join-Path $PSScriptRoot "..\viewer\index.html")).Path
$ViewerRel = "../viewer"
$script:ViewerEnabled = -not $NoLiveViewer
$script:FaBundleIdContext = ''
$script:MaxFaEvents = 10000
$script:MaxFaProperties = 10000
$script:FaEvents = [System.Collections.Generic.List[object]]::new()
$script:FaProperties = [System.Collections.Generic.List[object]]::new()
$script:FaPropertyLatest = @{}
$script:FaCaptureActive = $true
function Read-FaFilterListFile {
    param([string]$FilePath)
    $full = Join-Path $PSScriptRoot $FilePath
    if (-not (Test-Path -LiteralPath $full)) { return @() }
    $raw = Get-Content -LiteralPath $full -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    if ($raw -match "[\r\n]") {
        return @($raw -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    }
    return @($raw.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
}

$SkipParamKeys = @(
    'ga_event_origin(_o)',
    'ga_screen_class(_sc)',
    'ga_screen_id(_si)',
    'firebase_event_origin(_o)',
    'firebase_screen_class(_sc)',
    'firebase_screen_id(_si)'
)
function Get-FaConfigStringList {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @($Value.Trim())
    }
    return @($Value | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
}

function Import-FaFilterBundleJson {
    $path = Join-Path $PSScriptRoot "fa_filter_config.json"
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        $obj = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($obj.events) {
            $script:IncludeEvents = @(Get-FaConfigStringList $obj.events.include)
            $script:ExcludeEvents = @(Get-FaConfigStringList $obj.events.exclude)
        }
        if ($obj.properties) {
            $script:IncludeProperties = @(Get-FaConfigStringList $obj.properties.include)
            $script:ExcludeProperties = @(Get-FaConfigStringList $obj.properties.exclude)
        }
        if ($obj.eventParams) {
            $script:IncludeEventParams = @(Get-FaConfigStringList $obj.eventParams.include)
            $script:ExcludeEventParams = @(Get-FaConfigStringList $obj.eventParams.exclude)
        }
        return $true
    }
    catch {
        Write-Warning "fa_filter_config.json: $($_.Exception.Message)"
        return $false
    }
}

$IncludeEvents = @()
$ExcludeEvents = @()
$IncludeProperties = @()
$ExcludeProperties = @()
$IncludeEventParams = @()
$ExcludeEventParams = @()
if (-not (Import-FaFilterBundleJson)) {
    $IncludeEvents = @(Read-FaFilterListFile $IncludeFile)
    $ExcludeEvents = @(Read-FaFilterListFile $ExcludeFile)
    $IncludeProperties = @(Read-FaFilterListFile $IncludePropertyFile)
    $ExcludeProperties = @(Read-FaFilterListFile $ExcludePropertyFile)
    $IncludeEventParams = @(Read-FaFilterListFile $IncludeEventParamFile)
    $ExcludeEventParams = @(Read-FaFilterListFile $ExcludeEventParamFile)
}
function Get-FaParamEntryValue {
    param($Entry)
    if ($Entry -is [hashtable] -and $Entry.ContainsKey("value")) {
        return [string]$Entry["value"]
    }
    return [string]$Entry
}

function Parse-FaParamFilterRule {
    param([string]$Raw)
    $s = $Raw.Trim()
    $eq = $s.IndexOf("=")
    if ($eq -lt 0) {
        return @{ Name = $s; Value = $null }
    }
    $name = $s.Substring(0, $eq).Trim()
    $val = $s.Substring($eq + 1).Trim()
    if ([string]::IsNullOrEmpty($val)) { $val = $null }
    return @{ Name = $name; Value = $val }
}

function Test-FaParamRuleMatch {
    param([hashtable]$Params, $Rule)
    if (-not $Params -or -not $Rule.Name -or -not $Params.ContainsKey($Rule.Name)) {
        return $false
    }
    if ($null -eq $Rule.Value) { return $true }
    $actual = Get-FaParamEntryValue $Params[$Rule.Name]
    return ($actual.Trim().ToLowerInvariant() -eq $Rule.Value.Trim().ToLowerInvariant())
}

function Test-EventParamFilter {
    param(
        [hashtable]$Params,
        [string[]]$IncludeList,
        [string[]]$ExcludeList
    )
    if ($IncludeList.Count -gt 0) {
        $matched = $false
        foreach ($ruleRaw in $IncludeList) {
            $rule = Parse-FaParamFilterRule $ruleRaw
            if ($rule.Name -and (Test-FaParamRuleMatch $Params $rule)) {
                $matched = $true
                break
            }
        }
        if (-not $matched) { return $false }
    }
    if ($ExcludeList.Count -gt 0) {
        foreach ($ruleRaw in $ExcludeList) {
            $rule = Parse-FaParamFilterRule $ruleRaw
            if ($rule.Name -and (Test-FaParamRuleMatch $Params $rule)) {
                return $false
            }
        }
    }
    return $true
}
function Update-FaBundleIdFromLine {
    param([string]$Line)
    # FA-SVC (tien trinh GMS dung chung) log `appId: com.foo` (hai cham) hoac
    # `EES (not )loaded for: com.foo` ngay truoc moi `Logging event:` — tin hieu
    # dang tin de gan bundle khi debug nhieu app cung luc.
    if ($Line -match '(?:[^a-zA-Z_]|^)appId:\s*(?<id>[a-zA-Z][a-zA-Z0-9._]+)') {
        $script:FaBundleIdContext = $Matches['id'].Trim()
        return
    }
    if ($Line -match 'EES (?:not )?loaded for:\s*(?<id>[a-zA-Z][a-zA-Z0-9._]+)') {
        $script:FaBundleIdContext = $Matches['id'].Trim()
        return
    }
    if ($Line -match 'Event(?:\s+recorded)?:\s*Event\{[^}]*appId=[''"]?(?<id>[^''",}\s]+)') {
        $script:FaBundleIdContext = $Matches['id'].Trim()
        return
    }
    if ($Line -match "appId='(?<id>[^']+)'") {
        $script:FaBundleIdContext = $Matches['id'].Trim()
        return
    }
    if ($Line -match 'App package, google app id:\s*(?<id>[a-zA-Z][a-zA-Z0-9._]*)') {
        $script:FaBundleIdContext = $Matches['id'].Trim()
        return
    }
}
function Get-FaAdbDebugPackage {
    $raw = (& ./adb/adb shell getprop debug.firebase.analytics.app 2>$null | Out-String).Trim()
    if (-not $raw -or $raw -eq '.none.' -or $raw -eq '(null)') { return '' }
    $line = ($raw -split "`n", 2)[0].Trim()
    if ($line.StartsWith('[') -and $line.Contains(']')) {
        $line = $line.Substring($line.IndexOf(']') + 1).Trim()
    }
    if ($line -eq '.none.' -or $line -eq '(null)') { return '' }
    return $line
}
function Get-FaBundleIdForLine {
    param([string]$Line)
    if ($Line -match "appId='(?<id>[^']+)'") {
        return $Matches['id'].Trim()
    }
    if ($Line -match "appId=(?<id>[a-zA-Z][a-zA-Z0-9._]*)") {
        return $Matches['id'].Trim()
    }
    return $script:FaBundleIdContext
}
function Test-NameFilter {
    param(
        [string]$Name,
        [string[]]$IncludeList,
        [string[]]$ExcludeList
    )
    if ($IncludeList.Count -gt 0 -and $Name -notin $IncludeList) {
        return $false
    }
    if ($ExcludeList.Count -gt 0 -and $Name -in $ExcludeList) {
        return $false
    }
    return $true
}

function Test-PropertyFilter {
    param(
        [string]$Name,
        [string]$Value,
        [string[]]$IncludeList,
        [string[]]$ExcludeList
    )
    if ($IncludeList.Count -gt 0) {
        $matched = $false
        foreach ($ruleRaw in $IncludeList) {
            $rule = Parse-FaParamFilterRule $ruleRaw
            if (-not $rule.Name -or $Name -ne $rule.Name) { continue }
            if ($null -eq $rule.Value) {
                $matched = $true
                break
            }
            if ($Value.Trim().ToLowerInvariant() -eq $rule.Value.Trim().ToLowerInvariant()) {
                $matched = $true
                break
            }
        }
        if (-not $matched) { return $false }
    }
    if ($ExcludeList.Count -gt 0) {
        foreach ($ruleRaw in $ExcludeList) {
            $rule = Parse-FaParamFilterRule $ruleRaw
            if (-not $rule.Name -or $Name -ne $rule.Name) { continue }
            if ($null -eq $rule.Value) {
                return $false
            }
            if ($Value.Trim().ToLowerInvariant() -eq $rule.Value.Trim().ToLowerInvariant()) {
                return $false
            }
        }
    }
    return $true
}
function Get-FaValueType {
    param([string]$Value)
    $s = $Value.Trim()
    if ([string]::IsNullOrEmpty($s)) { return 'string' }
    if ($s -eq 'true' -or $s -eq 'false') { return 'boolean' }
    if ($s -eq 'null') { return 'null' }
    if ($s -match '^-?\d+$') { return 'int' }
    if ($s -match '^-?(?:\d+\.\d*|\.\d+)(?:[eE][+-]?\d+)?$' -or $s -match '^-?\d+[eE][+-]?\d+$') {
        return 'double'
    }
    return 'string'
}
function Parse-FaEventParams {
    param([string]$ParamsRaw)
    $result = [ordered]@{}
    if ([string]::IsNullOrWhiteSpace($ParamsRaw)) {
        return $result
    }
    foreach ($pair in ($ParamsRaw -split ',\s*')) {
        $eq = $pair.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $pair.Substring(0, $eq).Trim()
        $val = $pair.Substring($eq + 1).Trim()
        if ($key -in $SkipParamKeys) { continue }
        $result[$key] = @{
            value     = $val
            valueType = (Get-FaValueType -Value $val)
        }
    }
    return $result
}
function Parse-FaEventLine {
    param([string]$Line)
    if ($Line -notmatch '^(?<ts>\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3}).*?Logging event:.*?name=(?<name>[^,]+)') {
        return $null
    }
    $ts = $Matches['ts']
    $name = $Matches['name'].Trim()
    $paramsRaw = ''
    if ($Line -match 'params=Bundle\[\{(?<params>.*)\}\]') {
        $paramsRaw = $Matches['params']
    }
    return [pscustomobject]@{
        Timestamp = $ts
        Name      = $name
        BundleId  = (Get-FaBundleIdForLine -Line $Line)
        Params    = Parse-FaEventParams -ParamsRaw $paramsRaw
    }
}
function Parse-FaUserPropertyLine {
    param([string]$Line)
    if ($Line -notmatch '^(?<ts>\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3}).*?Setting user property(?:\s*\([^)]*\))?:\s*(?<name>[^,]+),\s*(?<value>.+)$') {
        return $null
    }
    return [pscustomobject]@{
        Timestamp = $Matches['ts']
        Name      = $Matches['name'].Trim()
        Value     = $Matches['value'].Trim()
        BundleId  = (Get-FaBundleIdForLine -Line $Line)
    }
}
function ConvertTo-FaJsonRecord {
    param($Parsed, [ValidateSet('event', 'user_property')][string]$Kind)
    if ($Kind -eq 'event') {
        $params = @{}
        foreach ($key in $Parsed.Params.Keys) {
            $params[$key] = $Parsed.Params[$key]
        }
        return @{
            type     = 'event'
            ts       = $Parsed.Timestamp
            name     = $Parsed.Name
            bundleId = $Parsed.BundleId
            params   = $params
        }
    }
    return @{
        type      = 'user_property'
        ts        = $Parsed.Timestamp
        name      = $Parsed.Name
        bundleId  = $Parsed.BundleId
        value     = $Parsed.Value
        valueType = (Get-FaValueType -Value $Parsed.Value)
    }
}
function Append-Utf8Text {
    param(
        [string]$FilePath,
        [string]$Text
    )
    if ([string]::IsNullOrEmpty($Text)) { return }
    $dir = Split-Path -Parent $FilePath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $fs = [System.IO.File]::Open(
        $FilePath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::ReadWrite
    )
    try {
        $fs.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Flush()
    }
    finally {
        $fs.Dispose()
    }
}
function Write-FaLoggingHtml {
    $dir = Split-Path -Parent $script:OutputFilePath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $bootstrapObj = @{
        events         = @($script:FaEvents.ToArray())
        properties     = @($script:FaProperties.ToArray())
        propertyLatest = $script:FaPropertyLatest
    }
    $recordsJson = ConvertTo-Json $bootstrapObj -Depth 10 -Compress
    $recordsJson = $recordsJson -replace '<', '\u003c' -replace '>', '\u003e' -replace '&', '\u0026'
    $filterJson = ConvertTo-Json @{
        events      = @{ include = @($IncludeEvents); exclude = @($ExcludeEvents) }
        eventParams = @{ include = @($IncludeEventParams); exclude = @($ExcludeEventParams) }
        properties  = @{ include = @($IncludeProperties); exclude = @($ExcludeProperties) }
    } -Depth 5 -Compress
    $filterJson = $filterJson -replace '<', '\u003c'
    $indexHtml = Get-Content -LiteralPath $ViewerIndex -Raw -Encoding UTF8
    $indexHtml = $indexHtml -replace 'href="/app\.css"', ('href="' + $ViewerRel + '/app.css"')
    $indexHtml = $indexHtml -replace 'src="/value_type\.js"', ('src="' + $ViewerRel + '/value_type.js"')
    $indexHtml = $indexHtml -replace 'src="/app\.js"', ('src="' + $ViewerRel + '/app.js"')
    $bootstrap = @"
  <script>
    window.__FA_FILE_MODE__ = true;
    window.__FA_BOOTSTRAP__ = $recordsJson;
    window.__FA_FILTER_CONFIG__ = $filterJson;
  </script>
"@
    $needle = '<script src="' + $ViewerRel + '/value_type.js"></script>'
    if ($indexHtml -notlike "*$needle*") {
        throw "Khong tim thay $needle trong viewer template."
    }
    $indexHtml = $indexHtml.Replace($needle, ($bootstrap.TrimEnd() + "`n  " + $needle))
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($script:OutputFilePath, $indexHtml, $utf8)
}
function Trim-FaProperties {
    while ($script:FaProperties.Count -gt $script:MaxFaProperties) {
        $script:FaProperties.RemoveAt(0)
    }
}
function Initialize-FaStreamFile {
    $dir = Split-Path -Parent $script:StreamFilePath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $fs = [System.IO.File]::Create($script:StreamFilePath)
    $fs.Close()
}
function Write-FaLog {
    param([hashtable]$JsonRecord)
    if (-not $JsonRecord) { return }
    if ($JsonRecord.type -eq 'event') {
        [void]$script:FaEvents.Add($JsonRecord)
        while ($script:FaEvents.Count -gt $script:MaxFaEvents) {
            $script:FaEvents.RemoveAt(0)
        }
    }
    elseif ($JsonRecord.type -eq 'user_property') {
        [void]$script:FaProperties.Add($JsonRecord)
        $bk = if ($JsonRecord.bundleId) { [string]$JsonRecord.bundleId } else { '' }
        if (-not $script:FaPropertyLatest.ContainsKey($bk)) {
            $script:FaPropertyLatest[$bk] = @{}
        }
        $script:FaPropertyLatest[$bk][$JsonRecord.name] = $JsonRecord
        Trim-FaProperties
    }
    if ($script:ViewerEnabled) {
        $json = $JsonRecord | ConvertTo-Json -Compress -Depth 6
        Append-Utf8Text -FilePath $script:StreamFilePath -Text ($json + "`n")
    }
    elseif ($script:FaCaptureActive) {
        Write-FaLoggingHtml
    }
}
function Test-FaViewerApiReady {
    param([int]$Port)
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/filter-config" -UseBasicParsing -TimeoutSec 3
        return ($r.StatusCode -eq 200)
    }
    catch {
        return $false
    }
}

function Stop-FaViewerOnPort {
    param([int]$Port)
    $conns = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    foreach ($c in $conns) {
        if ($c.OwningProcess) {
            Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
        }
    }
    if ($conns.Count -gt 0) {
        Start-Sleep -Milliseconds 800
    }
}

function Start-FaViewerServerProcess {
    $serverScript = Join-Path $PSScriptRoot "fa_viewer_server.ps1"
    $streamPath = Join-Path $PSScriptRoot $StreamFile
    $configDir = $PSScriptRoot
    $argString = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden " +
        "-File `"$serverScript`" -Port $ViewerPort -StreamFile `"$streamPath`" -ConfigDir `"$configDir`""
    Start-Process -FilePath "powershell.exe" -ArgumentList $argString | Out-Null
    Start-Sleep -Seconds 2
}

function Start-FaViewerServer {
    $portInUse = Get-NetTCPConnection -LocalPort $ViewerPort -State Listen -ErrorAction SilentlyContinue
    if ($portInUse -and -not (Test-FaViewerApiReady -Port $ViewerPort)) {
        Write-Host "Viewer cu (thieu API filter-config), khoi dong lai..."
        Stop-FaViewerOnPort -Port $ViewerPort
        $portInUse = $null
    }
    if ($portInUse) {
        Write-Host "Viewer (live): http://127.0.0.1:$ViewerPort/"
    }
    else {
        Start-FaViewerServerProcess
        Write-Host "Viewer (live): http://127.0.0.1:$ViewerPort/"
    }
    if (-not $NoBrowser) {
        Start-Process "http://127.0.0.1:$ViewerPort/"
    }
}
function Open-FaHtmlExport {
    if ($NoBrowser) { return }
    $uri = [System.Uri]::new($script:OutputFilePath).AbsoluteUri
    Start-Process $uri | Out-Null
}
function Stop-FaCapture {
    if (-not $script:FaCaptureActive) { return }
    $script:FaCaptureActive = $false
    Write-FaLoggingHtml
}
trap {
    Stop-FaCapture
    break
}
try {
    [Console]::TreatControlCAsInput = $false
    [void][Console]::CancelKeyPress.Add({
        param($sender, $e)
        $e.Cancel = $true
        Stop-FaCapture
        [Environment]::Exit(0)
    })
}
catch {
    # Khong co console tuong tac
}
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Stop-FaCapture
} | Out-Null
Write-Host "Output: $OutputFile (HTML snapshot khi dung capture)"
if ($script:ViewerEnabled) {
    Write-Host "Viewer live: http://127.0.0.1:$ViewerPort/ (SSE, cap nhat khong reload trang)"
    Start-FaViewerServer
    if ($Fresh -or -not (Test-Path -LiteralPath $script:StreamFilePath) -or (Get-Item -LiteralPath $script:StreamFilePath).Length -eq 0) {
        Initialize-FaStreamFile
    }
    else {
        Write-Host "Giu stream cu: $StreamFile (dung -Fresh de xoa session)"
    }
}
else {
    Write-Host "Viewer live: tat (-NoLiveViewer). Mo $OutputFile va F5 de cap nhat."
}
$script:FaEvents.Clear()
$script:FaProperties.Clear()
$script:FaPropertyLatest = @{}
if (-not $script:ViewerEnabled) {
    Write-FaLoggingHtml
    Open-FaHtmlExport
}
Write-Host "ADB: setprop FA, logcat -c, capturing... (Ctrl+C dung)"
./adb/adb shell setprop log.tag.FA VERBOSE
./adb/adb shell setprop log.tag.FA-SVC VERBOSE
$initBundle = Get-FaAdbDebugPackage
if ($initBundle) {
    $script:FaBundleIdContext = $initBundle
    Write-Host "Bundle context (seed getprop): $initBundle"
}
else {
    Write-Host "Bundle context: (se gan theo appId trong log FA-SVC)"
}
./adb/adb logcat -c
./adb/adb logcat -v time -s FA FA-SVC |
ForEach-Object {
    Update-FaBundleIdFromLine -Line $_
    $isEvent = $_ -match "Logging event:"
    $isUserProperty = $_ -match "Setting user property"
    if (-not $isEvent -and -not $isUserProperty) {
        return
    }
    if ($isEvent) {
        $parsed = Parse-FaEventLine -Line $_
        if (-not $parsed) { return }
        if (-not (Test-NameFilter -Name $parsed.Name -IncludeList $IncludeEvents -ExcludeList $ExcludeEvents)) {
            return
        }
        if (-not (Test-EventParamFilter -Params $parsed.Params -IncludeList $IncludeEventParams -ExcludeList $ExcludeEventParams)) {
            return
        }
        $json = ConvertTo-FaJsonRecord -Parsed $parsed -Kind 'event'
        Write-FaLog -JsonRecord $json
    }
    else {
        $parsed = Parse-FaUserPropertyLine -Line $_
        if (-not $parsed) { return }
        if (-not (Test-PropertyFilter -Name $parsed.Name -Value $parsed.Value -IncludeList $IncludeProperties -ExcludeList $ExcludeProperties)) {
            return
        }
        $json = ConvertTo-FaJsonRecord -Parsed $parsed -Kind 'user_property'
        Write-FaLog -JsonRecord $json
    }
}
Stop-FaCapture
