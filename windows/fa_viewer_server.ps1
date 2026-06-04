param(
    [int]$Port = 8765,
    [string]$StreamFile = "",
    [string]$ViewerRoot = "",
    [string]$ConfigDir = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($StreamFile)) {
    $StreamFile = Join-Path $PSScriptRoot "fa_logging_stream.jsonl"
}
if ([string]::IsNullOrWhiteSpace($ViewerRoot)) {
    $ViewerRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\viewer")).Path
}
if ([string]::IsNullOrWhiteSpace($ConfigDir)) {
    $ConfigDir = $PSScriptRoot
}

$mime = @{
    ".html" = "text/html; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".ico"  = "image/x-icon"
}

function Write-HttpBytes {
    param($Response, [byte[]]$Bytes, [string]$ContentType, [int]$Status = 200)
    $Response.StatusCode = $Status
    $Response.ContentType = $ContentType
    $Response.ContentLength64 = $Bytes.Length
    $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $Response.OutputStream.Close()
}

function Escape-JsonString {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    $s = [string]$Value
    $s = $s -replace '\\', '\\\\'
    $s = $s -replace '"', '\"'
    $s = $s -replace [char]8, '\b'
    $s = $s -replace [char]9, '\t'
    $s = $s -replace [char]10, '\n'
    $s = $s -replace [char]12, '\f'
    $s = $s -replace [char]13, '\r'
    return '"' + $s + '"'
}

function ConvertTo-JsonStringArray {
    param($Items)
    $arr = @(Get-ConfigStringList $Items)
    if ($arr.Count -eq 0) { return '[]' }
    return '[' + (($arr | ForEach-Object { Escape-JsonString $_ }) -join ',') + ']'
}

function ConvertTo-JsonArray {
    param($Items, [int]$Depth = 8)
    $arr = @($Items)
    if ($arr.Count -eq 0) { return '[]' }
    $parts = foreach ($item in $arr) {
        if ($item -is [string]) {
            Escape-JsonString $item
        }
        else {
            ConvertTo-Json $item -Depth $Depth -Compress
        }
    }
    return '[' + ($parts -join ',') + ']'
}

function Write-HttpJson {
    param($Response, $Object, [int]$Status = 200)
    $json = $Object | ConvertTo-Json -Depth 8 -Compress
    Write-HttpBytes -Response $Response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($json)) -ContentType "application/json; charset=utf-8" -Status $Status
}

function ConvertTo-FilterConfigJsonFragment {
    param($Include, $Exclude)
    return '{"include":' + (ConvertTo-JsonStringArray $Include) + ',"exclude":' + (ConvertTo-JsonStringArray $Exclude) + '}'
}

function Write-FilterConfigJson {
    param($Response, $Include, $Exclude, [int]$Status = 200)
    $json = '{"ok":true,' + (ConvertTo-FilterConfigJsonFragment $Include $Exclude).TrimStart('{')
    Write-HttpBytes -Response $Response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($json)) -ContentType "application/json; charset=utf-8" -Status $Status
}

function Write-AllFilterConfigJson {
    param($Response, $Saved, [int]$Status = 200)
    $json = '{"ok":true,"events":' + (ConvertTo-FilterConfigJsonFragment $Saved.events.include $Saved.events.exclude) +
        ',"eventParams":' + (ConvertTo-FilterConfigJsonFragment $Saved.eventParams.include $Saved.eventParams.exclude) +
        ',"properties":' + (ConvertTo-FilterConfigJsonFragment $Saved.properties.include $Saved.properties.exclude) + '}'
    Write-HttpBytes -Response $Response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($json)) -ContentType "application/json; charset=utf-8" -Status $Status
}

function Write-HttpJsonArray {
    param($Response, $Items, [int]$Status = 200)
    $json = ConvertTo-JsonArray -Items $Items -Depth 8
    Write-HttpBytes -Response $Response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($json)) -ContentType "application/json; charset=utf-8" -Status $Status
}

function Write-HttpText {
    param($Response, [string]$Text, [string]$ContentType, [int]$Status = 200)
    $enc = [System.Text.Encoding]::UTF8
    Write-HttpBytes -Response $Response -Bytes ($enc.GetBytes($Text)) -ContentType $ContentType -Status $Status
}

function Read-NameListFromFile {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { return @() }
    $raw = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    if ($raw -match "[\r\n]") {
        return @($raw -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    }
    return @($raw.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
}

function Get-ConfigStringList {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @($Value.Trim())
    }
    return @($Value | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
}

function Get-EventFilterConfig {
    @{
        include = @(Read-NameListFromFile (Join-Path $ConfigDir "include_event.txt"))
        exclude = @(Read-NameListFromFile (Join-Path $ConfigDir "exclude_event.txt"))
    }
}

function Get-PropertyFilterConfig {
    @{
        include = @(Read-NameListFromFile (Join-Path $ConfigDir "include_property.txt"))
        exclude = @(Read-NameListFromFile (Join-Path $ConfigDir "exclude_property.txt"))
    }
}

function Write-NameListToFile {
    param(
        [string]$FilePath,
        [string[]]$Names
    )
    $dir = Split-Path -Parent $FilePath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $clean = @($Names | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
    if ($clean.Count -eq 0) {
        $content = ''
    }
    elseif ($clean | Where-Object { $_ -match ',' }) {
        $content = $clean -join "`n"
    }
    else {
        $content = $clean -join ','
    }
    $tmp = "$FilePath.tmp"
    $enc = [System.Text.UTF8Encoding]::new($false)
    $lastErr = $null
    for ($i = 0; $i -lt 5; $i++) {
        try {
            [System.IO.File]::WriteAllText($tmp, $content, $enc)
            if ([System.IO.File]::Exists($FilePath)) {
                [System.IO.File]::Delete($FilePath)
            }
            [System.IO.File]::Move($tmp, $FilePath)
            return
        }
        catch {
            $lastErr = $_
            Start-Sleep -Milliseconds (50 * ($i + 1))
        }
    }
    if ($lastErr) { throw $lastErr }
}

function Get-AllFilterConfig {
    @{
        events      = Get-EventFilterConfig
        eventParams = Get-EventParamFilterConfig
        properties  = Get-PropertyFilterConfig
    }
}

function Set-AllFilterConfig {
    param($Config)
    $events = if ($Config.events) { $Config.events } else { @{ include = @(); exclude = @() } }
    $eventParams = if ($Config.eventParams) { $Config.eventParams } else { @{ include = @(); exclude = @() } }
    $properties = if ($Config.properties) { $Config.properties } else { @{ include = @(); exclude = @() } }
    return @{
        events      = Set-EventFilterConfig -Config $events
        eventParams = Set-EventParamFilterConfig -Config $eventParams
        properties  = Set-PropertyFilterConfig -Config $properties
    }
}

function Get-FilterBundleFilePath {
    Join-Path $script:ConfigDir "fa_filter_config.json"
}

function Read-FilterBundleFromFile {
    $path = Get-FilterBundleFilePath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-FilterBundleConfig {
    $obj = Read-FilterBundleFromFile
    if ($obj) {
        return @{
            events = @{
                include = @(Get-ConfigStringList $obj.events.include)
                exclude = @(Get-ConfigStringList $obj.events.exclude)
            }
            eventParams = @{
                include = @(Get-ConfigStringList $obj.eventParams.include)
                exclude = @(Get-ConfigStringList $obj.eventParams.exclude)
            }
            properties = @{
                include = @(Get-ConfigStringList $obj.properties.include)
                exclude = @(Get-ConfigStringList $obj.properties.exclude)
            }
        }
    }
    return Get-AllFilterConfig
}

function Write-FilterBundleFile {
    param($Saved)
    $path = Get-FilterBundleFilePath
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = '{"version":1,"events":' + (ConvertTo-FilterConfigJsonFragment $Saved.events.include $Saved.events.exclude) +
        ',"eventParams":' + (ConvertTo-FilterConfigJsonFragment $Saved.eventParams.include $Saved.eventParams.exclude) +
        ',"properties":' + (ConvertTo-FilterConfigJsonFragment $Saved.properties.include $Saved.properties.exclude) + '}'
    $enc = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($path, $json, $enc)
}

function Set-FilterBundleConfig {
    param($Config)
    $saved = Set-AllFilterConfig -Config $Config
    Write-FilterBundleFile -Saved $saved
    return $saved
}

function Set-EventFilterConfig {
    param($Config)
    $include = Get-ConfigStringList $Config.include
    $exclude = Get-ConfigStringList $Config.exclude
    Write-NameListToFile (Join-Path $ConfigDir "include_event.txt") $include
    Write-NameListToFile (Join-Path $ConfigDir "exclude_event.txt") $exclude
    return @{
        include = $include
        exclude = $exclude
    }
}

function Set-PropertyFilterConfig {
    param($Config)
    $include = Get-ConfigStringList $Config.include
    $exclude = Get-ConfigStringList $Config.exclude
    Write-NameListToFile (Join-Path $ConfigDir "include_property.txt") $include
    Write-NameListToFile (Join-Path $ConfigDir "exclude_property.txt") $exclude
    return @{
        include = $include
        exclude = $exclude
    }
}

function Get-EventParamFilterConfig {
    @{
        include = @(Read-NameListFromFile (Join-Path $ConfigDir "include_event_param.txt"))
        exclude = @(Read-NameListFromFile (Join-Path $ConfigDir "exclude_event_param.txt"))
    }
}

function Set-EventParamFilterConfig {
    param($Config)
    $include = Get-ConfigStringList $Config.include
    $exclude = Get-ConfigStringList $Config.exclude
    Write-NameListToFile (Join-Path $ConfigDir "include_event_param.txt") $include
    Write-NameListToFile (Join-Path $ConfigDir "exclude_event_param.txt") $exclude
    return @{
        include = $include
        exclude = $exclude
    }
}

function Read-RequestJsonBody {
    param([System.Net.HttpListenerRequest]$Request)
    if (-not $Request.HasEntityBody) { return $null }
    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    try {
        $body = $reader.ReadToEnd()
    }
    finally {
        $reader.Close()
    }
    if ([string]::IsNullOrWhiteSpace($body)) { return $null }
    return ($body | ConvertFrom-Json)
}

function Read-SharedUtf8Lines {
    param([string]$FilePath)
    $lines = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $FilePath)) { return $lines }
    $fs = [System.IO.File]::Open(
        $FilePath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )
    try {
        $reader = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        while ($null -ne ($line = $reader.ReadLine())) {
            $lines.Add($line)
        }
    }
    finally {
        $fs.Dispose()
    }
    return $lines
}

function Get-StreamHistory {
    param([string]$StreamPath, [int]$MaxLines = 10000)
    $records = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $StreamPath)) { return $records }
    $lines = Read-SharedUtf8Lines -FilePath $StreamPath
    if (-not $lines.Count) { return $records }
    if ($lines.Count -gt $MaxLines) {
        $start = $lines.Count - $MaxLines
        $lines = $lines.GetRange($start, $MaxLines)
    }
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $records.Add(($line | ConvertFrom-Json))
        }
        catch {
            # bỏ dòng hỏng
        }
    }
    return $records
}

function Clear-StreamFile {
    param([string]$StreamPath)
    $dir = Split-Path -Parent $StreamPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $fs = [System.IO.File]::Open(
        $StreamPath,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::ReadWrite
    )
    $fs.Close()
}

function Serve-StaticFile {
    param($Context, [string]$RelPath)
    $safe = $RelPath.TrimStart("/").Replace("\", "/")
    if ($safe -match '\.\.') {
        Write-HttpText -Response $Context.Response -Text "Forbidden" -ContentType "text/plain" -Status 403
        return
    }
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "index.html" }
    $full = Join-Path $ViewerRoot $safe
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        Write-HttpText -Response $Context.Response -Text "Not found" -ContentType "text/plain" -Status 404
        return
    }
    $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
    $ct = $mime[$ext]
    if (-not $ct) { $ct = "application/octet-stream" }
    $bytes = [System.IO.File]::ReadAllBytes($full)
    Write-HttpBytes -Response $Context.Response -Bytes $bytes -ContentType $ct
}

function Write-SseData {
    param($Response, [string]$Data)
    $enc = [System.Text.Encoding]::UTF8
    $chunk = "data: $Data`n`n"
    $buf = $enc.GetBytes($chunk)
    $Response.OutputStream.Write($buf, 0, $buf.Length)
    $Response.OutputStream.Flush()
}

function Start-SseStream {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [string]$StreamPath
    )
    # offset 0: phát lại file khi F5 (giống Linux). Client dedup trùng với /api/history.
    $offset = 0L

    Write-SseData -Response $Response -Data '{"type":"connected"}'

    try {
        while ($Response.OutputStream.CanWrite) {
            if (-not (Test-Path -LiteralPath $StreamPath)) {
                Start-Sleep -Milliseconds 400
                continue
            }
            $fs = [System.IO.File]::Open(
                $StreamPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite
            )
            try {
                if ($fs.Length -lt $offset) { $offset = 0 }
                $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
                $reader = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
                while (-not $reader.EndOfStream) {
                    $line = $reader.ReadLine()
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    Write-SseData -Response $Response -Data $line
                }
                $offset = $fs.Position
            }
            finally {
                $fs.Dispose()
            }
            Start-Sleep -Milliseconds 300
        }
    }
    catch {
        # client disconnected
    }
    finally {
        try { $Response.OutputStream.Close() } catch { }
        try { $Response.Close() } catch { }
    }
}

function Invoke-FaHttpRequest {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string]$StreamPath,
        [string]$ViewerRootPath,
        [string]$ConfigDirPath
    )

    $path = $Context.Request.Url.LocalPath
    $method = $Context.Request.HttpMethod

    if ($path -eq "/api/filter-config" -and $method -eq "GET") {
        $script:ConfigDir = $ConfigDirPath
        Write-AllFilterConfigJson -Response $Context.Response -Saved (Get-FilterBundleConfig)
        return
    }

    if ($path -eq "/api/filter-config" -and $method -eq "POST") {
        try {
            $script:ConfigDir = $ConfigDirPath
            $body = Read-RequestJsonBody -Request $Context.Request
            if (-not $body) { $body = @{} }
            $saved = Set-FilterBundleConfig -Config $body
            Write-AllFilterConfigJson -Response $Context.Response -Saved $saved
        }
        catch {
            Write-HttpJson -Response $Context.Response -Object @{ error = $_.Exception.Message } -Status 500
        }
        return
    }

    if ($path -eq "/api/config/all" -and $method -eq "GET") {
        $script:ConfigDir = $ConfigDirPath
        Write-AllFilterConfigJson -Response $Context.Response -Saved (Get-FilterBundleConfig)
        return
    }

    if ($path -eq "/api/config/all" -and $method -eq "POST") {
        try {
            $script:ConfigDir = $ConfigDirPath
            $body = Read-RequestJsonBody -Request $Context.Request
            if (-not $body) { $body = @{} }
            $saved = Set-FilterBundleConfig -Config $body
            Write-AllFilterConfigJson -Response $Context.Response -Saved $saved
        }
        catch {
            Write-HttpJson -Response $Context.Response -Object @{ error = $_.Exception.Message } -Status 500
        }
        return
    }

    if ($path -eq "/api/config/events" -and $method -eq "GET") {
        $script:ConfigDir = $ConfigDirPath
        $cfg = Get-EventFilterConfig
        Write-FilterConfigJson -Response $Context.Response -Include $cfg.include -Exclude $cfg.exclude
        return
    }

    if ($path -eq "/api/config/events" -and $method -eq "POST") {
        try {
            $script:ConfigDir = $ConfigDirPath
            $body = Read-RequestJsonBody -Request $Context.Request
            if (-not $body) { $body = @{ include = @(); exclude = @() } }
            $saved = Set-EventFilterConfig -Config $body
            Write-FilterConfigJson -Response $Context.Response -Include $saved.include -Exclude $saved.exclude
        }
        catch {
            Write-HttpJson -Response $Context.Response -Object @{ error = $_.Exception.Message } -Status 500
        }
        return
    }

    if ($path -in @("/api/config/event-params", "/api/config/event_params") -and $method -eq "GET") {
        $script:ConfigDir = $ConfigDirPath
        $cfg = Get-EventParamFilterConfig
        Write-FilterConfigJson -Response $Context.Response -Include $cfg.include -Exclude $cfg.exclude
        return
    }

    if ($path -in @("/api/config/event-params", "/api/config/event_params") -and $method -eq "POST") {
        try {
            $script:ConfigDir = $ConfigDirPath
            $body = Read-RequestJsonBody -Request $Context.Request
            if (-not $body) { $body = @{ include = @(); exclude = @() } }
            $saved = Set-EventParamFilterConfig -Config $body
            Write-FilterConfigJson -Response $Context.Response -Include $saved.include -Exclude $saved.exclude
        }
        catch {
            Write-HttpJson -Response $Context.Response -Object @{ error = $_.Exception.Message } -Status 500
        }
        return
    }

    if ($path -eq "/api/config/properties" -and $method -eq "GET") {
        $script:ConfigDir = $ConfigDirPath
        $cfg = Get-PropertyFilterConfig
        Write-FilterConfigJson -Response $Context.Response -Include $cfg.include -Exclude $cfg.exclude
        return
    }

    if ($path -eq "/api/config/properties" -and $method -eq "POST") {
        try {
            $script:ConfigDir = $ConfigDirPath
            $body = Read-RequestJsonBody -Request $Context.Request
            if (-not $body) { $body = @{ include = @(); exclude = @() } }
            $saved = Set-PropertyFilterConfig -Config $body
            Write-FilterConfigJson -Response $Context.Response -Include $saved.include -Exclude $saved.exclude
        }
        catch {
            Write-HttpJson -Response $Context.Response -Object @{ error = $_.Exception.Message } -Status 500
        }
        return
    }

    if ($path -eq "/api/history" -and $method -eq "GET") {
        Write-HttpJsonArray -Response $Context.Response -Items (Get-StreamHistory -StreamPath $StreamPath)
        return
    }

    if ($path -eq "/api/clear" -and $method -eq "POST") {
        try {
            Clear-StreamFile -StreamPath $StreamPath
            Write-HttpJson -Response $Context.Response -Object @{ ok = $true }
        }
        catch {
            Write-HttpJson -Response $Context.Response -Object @{ error = $_.Exception.Message } -Status 500
        }
        return
    }

    if ($path -eq "/events" -and $method -eq "GET") {
        $res = $Context.Response
        $res.StatusCode = 200
        $res.ContentType = "text/event-stream; charset=utf-8"
        $res.Headers.Add("Cache-Control", "no-cache")
        $res.Headers.Add("Connection", "keep-alive")
        $scriptPath = $PSCommandPath
        [void][powershell]::Create().AddScript({
            param($SourceScript, $Response, $Stream)
            . $SourceScript
            Start-SseStream -Response $Response -StreamPath $Stream
        }).AddArgument($scriptPath).AddArgument($res).AddArgument($StreamPath).BeginInvoke()
        return
    }

    if ($method -eq "GET") {
        $script:ViewerRoot = $ViewerRootPath
        $rel = if ($path -eq "/") { "index.html" } else { $path.TrimStart("/") }
        Serve-StaticFile -Context $Context -RelPath $rel
        return
    }

    Write-HttpText -Response $Context.Response -Text "Not found" -ContentType "text/plain" -Status 404
}

# Chỉ chạy listener khi gọi trực tiếp (không dot-source cho worker SSE)
if ($MyInvocation.InvocationName -ne '.') {

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://127.0.0.1:$Port/")
    $listener.Start()

    Write-Host "FA viewer: http://127.0.0.1:$Port/"
    Write-Host "Stream file: $StreamFile"
    Write-Host "Config dir:  $ConfigDir"

    try {
        while ($listener.IsListening) {
            $ctx = $listener.GetContext()
            try {
                Invoke-FaHttpRequest -Context $ctx -StreamPath $StreamFile -ViewerRootPath $ViewerRoot -ConfigDirPath $ConfigDir
            }
            catch {
                try {
                    Write-HttpText -Response $ctx.Response -Text $_.Exception.Message -ContentType "text/plain" -Status 500
                }
                catch {
                    # client đã ngắt
                }
            }
        }
    }
    finally {
        $listener.Stop()
        $listener.Close()
    }
}
