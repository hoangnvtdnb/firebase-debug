# Chỉ chạy viewer (khi capture đang chạy ở terminal khác hoặc đọc stream có sẵn)
param([int]$Port = 8765)

$serverScript = Join-Path $PSScriptRoot "fa_viewer_server.ps1"
$streamPath = Join-Path $PSScriptRoot "fa_logging_stream.jsonl"
if (-not (Test-Path -LiteralPath $streamPath)) {
    New-Item -ItemType File -Path $streamPath -Force | Out-Null
}

function Test-FaViewerApiReady {
    param([int]$P)
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$P/api/filter-config" -UseBasicParsing -TimeoutSec 3
        return ($r.StatusCode -eq 200)
    }
    catch { return $false }
}

function Stop-FaViewerOnPort {
    param([int]$P)
    foreach ($c in @(Get-NetTCPConnection -LocalPort $P -State Listen -ErrorAction SilentlyContinue)) {
        if ($c.OwningProcess) {
            Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Milliseconds 800
}

$listening = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
if ($listening -and -not (Test-FaViewerApiReady -P $Port)) {
    Write-Host "Dừng viewer cũ (thiếu API filter-config)..."
    Stop-FaViewerOnPort -Port $Port
}

Write-Host "Mở http://127.0.0.1:$Port/"
Start-Process "http://127.0.0.1:$Port/"
& $serverScript -Port $Port -StreamFile $streamPath -ConfigDir $PSScriptRoot
