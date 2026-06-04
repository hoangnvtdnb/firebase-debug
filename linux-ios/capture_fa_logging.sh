#!/usr/bin/env bash
# Firebase Analytics capture từ iOS (idevicesyslog) + viewer (parity linux/Android)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

OUTPUT_FILE="fa_logging_results_ios.txt"
OUTPUT_HTML="fa_logging_results_ios.html"
STREAM_FILE="fa_logging_stream.jsonl"
VIEWER_PORT=8766
NO_VIEWER=0
NO_LIVE_VIEWER=0
NO_BROWSER=0
FRESH=0
IOS_BUNDLE=""
IOS_UDID=""
VIEWER_PID=""
VIEWER_INDEX="$SCRIPT_DIR/../viewer/index_ios.html"
VIEWER_REL="../viewer"

ENGINE="$SCRIPT_DIR/fa_capture_engine_ios.py"
SERVE="$SCRIPT_DIR/../viewer/serve.py"

usage() {
  cat <<'EOF'
Usage: ./capture_fa_logging.sh [options]

Options:
  --bundle ID              CFBundleIdentifier (gán bundle trên timeline; khuyến nghị)
  --udid UDID              UDID thiết bị (nhiều máy cắm USB)
  --no-viewer              Chỉ file text (không HTTP viewer, không HTML)
  --no-live-viewer         Chỉ file HTML, không viewer HTTP
  --no-browser             Viewer chạy, không mở browser
  --fresh                  Xóa stream cũ, session mới
  --viewer-port PORT       Cổng viewer (mặc định 8766 — tránh trùng Android 8765)
  -h, --help               Hiện trợ giúp

Yêu cầu: libimobiledevice (idevicesyslog, idevice_id). App iOS bật -FIRDebugEnabled
và -FIRAnalyticsVerboseLoggingEnabled (Xcode scheme hoặc code).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle)
      IOS_BUNDLE="${2:?Missing bundle id}"
      shift
      ;;
    --udid)
      IOS_UDID="${2:?Missing udid}"
      shift
      ;;
    --no-viewer) NO_VIEWER=1 ;;
    --no-live-viewer) NO_LIVE_VIEWER=1 ;;
    --no-browser) NO_BROWSER=1 ;;
    --fresh) FRESH=1 ;;
    --viewer-port)
      VIEWER_PORT="${2:?Missing port}"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ -z "$IOS_BUNDLE" && -n "${FA_IOS_BUNDLE:-}" ]]; then
  IOS_BUNDLE="$FA_IOS_BUNDLE"
fi
if [[ -z "$IOS_UDID" && -n "${FA_IOS_UDID:-}" ]]; then
  IOS_UDID="$FA_IOS_UDID"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required (capture engine + viewer)." >&2
  exit 1
fi

if ! command -v idevicesyslog >/dev/null 2>&1; then
  echo "ERROR: idevicesyslog not found. Install libimobiledevice:" >&2
  echo "  sudo apt install -y libimobiledevice-utils usbmuxd" >&2
  echo "Xem linux-ios/run_command.txt" >&2
  exit 1
fi

if ! command -v idevice_id >/dev/null 2>&1; then
  echo "ERROR: idevice_id not found (gói libimobiledevice-utils)." >&2
  exit 1
fi

read_csv_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  tr ',' '\n' <"$file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' || true
}

mapfile -t INCLUDE_EVENTS < <(read_csv_file "include_event.txt")
mapfile -t EXCLUDE_EVENTS < <(read_csv_file "exclude_event.txt")
mapfile -t INCLUDE_PROPS < <(read_csv_file "include_property.txt")
mapfile -t EXCLUDE_PROPS < <(read_csv_file "exclude_property.txt")

port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -qE ":${port}[[:space:]]"
    return $?
  fi
  python3 - "$port" <<'PY'
import socket, sys
p = int(sys.argv[1])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(0.3)
try:
    sys.exit(0 if s.connect_ex(("127.0.0.1", p)) == 0 else 1)
finally:
    s.close()
PY
}

open_browser() {
  local url="$1"
  if [[ "$NO_BROWSER" -eq 1 ]]; then
    return
  fi
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
  elif command -v sensible-browser >/dev/null 2>&1; then
    sensible-browser "$url" >/dev/null 2>&1 &
  else
    echo "Open in browser: $url"
  fi
}

http_code() {
  curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://127.0.0.1:${VIEWER_PORT}$1" 2>/dev/null || echo "000"
}

viewer_api_ready() {
  [[ "$(http_code /api/filter-config)" == "200" && "$(http_code /)" == "200" ]]
}

stop_viewer_on_port() {
  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${VIEWER_PORT}/tcp" 2>/dev/null || true
    sleep 1
    return
  fi
  if command -v lsof >/dev/null 2>&1; then
    local pids
    pids="$(lsof -ti ":${VIEWER_PORT}" 2>/dev/null || true)"
    if [[ -n "$pids" ]]; then
      kill $pids 2>/dev/null || true
      sleep 1
    fi
  fi
}

start_viewer() {
  local url="http://127.0.0.1:${VIEWER_PORT}/"
  if port_in_use "$VIEWER_PORT"; then
    if ! viewer_api_ready; then
      echo "Viewer cũ (thiếu API), khởi động lại..."
      stop_viewer_on_port
    else
      echo "Viewer đã chạy: $url"
      open_browser "$url"
      return
    fi
  fi

  if [[ ! -f "$SERVE" ]]; then
    echo "WARNING: Viewer script not found: $SERVE" >&2
    return
  fi

  nohup python3 "$SERVE" \
    --port "$VIEWER_PORT" \
    --stream "$SCRIPT_DIR/$STREAM_FILE" \
    --config "$SCRIPT_DIR" \
    >>"$SCRIPT_DIR/fa_viewer_server.log" 2>&1 &
  VIEWER_PID=$!
  disown "$VIEWER_PID" 2>/dev/null || true
  sleep 2

  if port_in_use "$VIEWER_PORT"; then
    echo "Viewer: $url (pid $VIEWER_PID)"
    open_browser "$url"
  else
    echo "WARNING: Viewer không khởi động. Xem fa_viewer_server.log hoặc ./start_fa_viewer.sh" >&2
  fi
}

trap true EXIT

LIVE_VIEWER=1
WRITE_STREAM=1
WRITE_HTML=1
INCREMENTAL_HTML=0

if [[ "$NO_VIEWER" -eq 1 ]]; then
  LIVE_VIEWER=0
  WRITE_STREAM=0
  WRITE_HTML=0
elif [[ "$NO_LIVE_VIEWER" -eq 1 ]]; then
  LIVE_VIEWER=0
  WRITE_STREAM=0
  INCREMENTAL_HTML=1
fi

echo "Include events: ${INCLUDE_EVENTS[*]:-(all)}"
echo "Exclude events: ${EXCLUDE_EVENTS[*]:-(none)}"
echo "Include properties: ${INCLUDE_PROPS[*]:-(all)}"
echo "Exclude properties: ${EXCLUDE_PROPS[*]:-(none)}"
echo "----------------------------------------"

if [[ "$LIVE_VIEWER" -eq 1 ]]; then
  start_viewer
  if [[ "$FRESH" -eq 1 || ! -s "$STREAM_FILE" ]]; then
    : >"$STREAM_FILE"
  else
    echo "Giữ stream cũ: $STREAM_FILE (dùng --fresh để xóa session)"
  fi
  echo "Viewer live: http://127.0.0.1:${VIEWER_PORT}/ (SSE)"
elif [[ "$NO_LIVE_VIEWER" -eq 1 ]]; then
  echo "Viewer live: tắt. Mở $OUTPUT_HTML và F5 để cập nhật."
fi

: >"$OUTPUT_FILE"

if [[ "$NO_LIVE_VIEWER" -eq 1 && "$WRITE_HTML" -eq 1 ]]; then
  python3 "$ENGINE" \
    --output "$OUTPUT_FILE" \
    --stream "$STREAM_FILE" \
    --config-dir "$SCRIPT_DIR" \
    --html-output "$OUTPUT_HTML" \
    --viewer-index "$VIEWER_INDEX" \
    --viewer-rel "$VIEWER_REL" \
    --init-html-only
  open_browser "file://$SCRIPT_DIR/$OUTPUT_HTML"
fi

echo "Checking iOS device (USB)..."
device_list="$(idevice_id -l 2>&1)" || device_list=""
if [[ -z "${device_list//[$'\t\r\n ']/}" ]]; then
  echo "ERROR: No iOS device detected." >&2
  echo "  - Cắm USB, mở khóa iPhone, chọn Trust This Computer" >&2
  echo "  - iOS 16+: Settings → Privacy & Security → Developer Mode" >&2
  echo "  - Chạy: idevice_id -l" >&2
  if [[ -n "$device_list" ]]; then
    echo "$device_list" >&2
  fi
  exit 1
fi

if [[ -z "$IOS_UDID" ]]; then
  IOS_UDID="$(printf '%s\n' "$device_list" | head -n1 | tr -d '\r')"
fi

echo "Device UDID: $IOS_UDID"
if [[ -n "$IOS_BUNDLE" ]]; then
  echo "Bundle id (--bundle): $IOS_BUNDLE"
else
  echo "Bundle id: (chưa set — dùng --bundle com.your.app hoặc FA_IOS_BUNDLE)"
fi

echo "Start capturing idevicesyslog (Firebase Analytics)..."
echo "Output text: $OUTPUT_FILE"
if [[ "$WRITE_HTML" -eq 1 ]]; then
  echo "Output HTML: $OUTPUT_HTML"
fi
if [[ "$WRITE_STREAM" -eq 1 ]]; then
  echo "Stream (viewer): $STREAM_FILE"
fi
echo "Press Ctrl+C to stop."
echo "----------------------------------------"

ENGINE_CMD=(
  python3 -u "$ENGINE"
  --output "$OUTPUT_FILE"
  --stream "$STREAM_FILE"
  --config-dir "$SCRIPT_DIR"
)
if [[ "$WRITE_STREAM" -eq 1 ]]; then
  ENGINE_CMD+=(--write-stream)
fi
if [[ "$WRITE_HTML" -eq 1 ]]; then
  ENGINE_CMD+=(
    --html-output "$OUTPUT_HTML"
    --viewer-index "$VIEWER_INDEX"
    --viewer-rel "$VIEWER_REL"
  )
fi
if [[ "$INCREMENTAL_HTML" -eq 1 ]]; then
  ENGINE_CMD+=(--incremental-html)
fi
if [[ -n "$IOS_BUNDLE" ]]; then
  ENGINE_CMD+=(--initial-bundle "$IOS_BUNDLE")
fi

SYSLOG_CMD=(idevicesyslog -u "$IOS_UDID")
# Bundle chỉ gán lên timeline (--initial-bundle), không dùng -m idevicesyslog
# vì dòng [Firebase/Analytics] thường không chứa CFBundleIdentifier.

"${SYSLOG_CMD[@]}" 2>/dev/null | grep --line-buffered -E \
  'Firebase/Analytics|FIRAnalytics|Logging event|Setting user property' \
  | "${ENGINE_CMD[@]}"
