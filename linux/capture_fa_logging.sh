#!/usr/bin/env bash
# Firebase Analytics capture + viewer (parity with windows/capture_fa_logging.ps1)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

OUTPUT_FILE="fa_logging_results_adb.txt"
OUTPUT_HTML="fa_logging_results_adb.html"
STREAM_FILE="fa_logging_stream.jsonl"
VIEWER_PORT=8765
NO_VIEWER=0
NO_LIVE_VIEWER=0
NO_BROWSER=0
FRESH=0
VIEWER_PID=""
VIEWER_INDEX="$SCRIPT_DIR/../viewer/index.html"
VIEWER_REL="../viewer"

ADB="$SCRIPT_DIR/adb/adb"
ENGINE="$SCRIPT_DIR/fa_capture_engine.py"
SERVE="$SCRIPT_DIR/../viewer/serve.py"

usage() {
  cat <<'EOF'
Usage: ./capture_fa_logging.sh [options]

Options:
  --no-viewer              Chỉ terminal + file text (không HTTP viewer, không HTML)
  --no-live-viewer         Chỉ file HTML (cập nhật từng event), không viewer HTTP
  --no-browser             Viewer chạy, không mở browser
  --fresh                  Xóa stream cũ, bắt đầu session mới
  --viewer-port PORT       Cổng viewer (mặc định 8765)
  -h, --help               Hiện trợ giúp
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required (capture engine + viewer)." >&2
  exit 1
fi

if [[ ! -x "$ADB" ]]; then
  chmod +x "$ADB" 2>/dev/null || true
fi

if [[ ! -x "$ADB" ]]; then
  echo "ERROR: adb not found or not executable: $ADB" >&2
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
  elif command -v wslview >/dev/null 2>&1; then
    wslview "$url" >/dev/null 2>&1 &
  else
    echo "Open in browser: $url"
  fi
}

http_code() {
  curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://127.0.0.1:${VIEWER_PORT}$1" 2>/dev/null || echo "000"
}

viewer_api_ready() {
  # Viewer "khỏe" khi cả API filter-config lẫn trang gốc đều trả 200
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
    return
  fi
  # Fallback không cần fuser/lsof: tìm PID đang listen qua /proc rồi kill
  python3 - "$VIEWER_PORT" <<'PY' || true
import os, signal, sys, time, glob

port = int(sys.argv[1])
want = f"{port:04X}"


def listen_inodes():
    inodes = set()
    for proc in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(proc, "r", encoding="utf-8") as f:
                next(f, None)
                for line in f:
                    parts = line.split()
                    if len(parts) < 10:
                        continue
                    local, state, inode = parts[1], parts[3], parts[9]
                    if state != "0A":  # 0A = LISTEN
                        continue
                    if local.rsplit(":", 1)[-1].upper() == want:
                        inodes.add(inode)
        except OSError:
            pass
    return inodes


def pids_for(inodes):
    targets = {f"socket:[{i}]" for i in inodes}
    pids = set()
    for fd in glob.glob("/proc/[0-9]*/fd/*"):
        try:
            if os.readlink(fd) in targets:
                pids.add(int(fd.split("/")[2]))
        except OSError:
            pass
    return pids


inodes = listen_inodes()
if not inodes:
    sys.exit(0)
pids = pids_for(inodes)
for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
time.sleep(1)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
PY
  sleep 1
}

start_viewer() {
  local url="http://127.0.0.1:${VIEWER_PORT}/"
  if port_in_use "$VIEWER_PORT"; then
    if ! viewer_api_ready; then
      echo "Viewer cũ (thiếu API filter-config), khởi động lại..."
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
    echo "WARNING: Viewer không khởi động. Xem fa_viewer_server.log hoặc chạy: ./start_fa_viewer.sh" >&2
  fi
}

cleanup() {
  if [[ -n "$VIEWER_PID" ]] && kill -0 "$VIEWER_PID" 2>/dev/null; then
    : # giữ viewer chạy sau khi dừng capture (giống Windows)
  fi
}
trap cleanup EXIT

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
  echo "Viewer live: http://127.0.0.1:${VIEWER_PORT}/ (SSE, không reload trang)"
elif [[ "$NO_LIVE_VIEWER" -eq 1 ]]; then
  echo "Viewer live: tắt (--no-live-viewer). Mở $OUTPUT_HTML và F5 để cập nhật."
else
  echo "Viewer live: tắt (--no-viewer)"
fi

: >"$OUTPUT_FILE"

if [[ "$NO_LIVE_VIEWER" -eq 1 && "$WRITE_HTML" -eq 1 ]]; then
  INIT_HTML_CMD=(
    python3 "$ENGINE"
    --output "$OUTPUT_FILE"
    --stream "$STREAM_FILE"
    --config-dir "$SCRIPT_DIR"
    --html-output "$OUTPUT_HTML"
    --viewer-index "$VIEWER_INDEX"
    --viewer-rel "$VIEWER_REL"
    --init-html-only
  )
  "${INIT_HTML_CMD[@]}"
  html_uri="file://$SCRIPT_DIR/$OUTPUT_HTML"
  open_browser "$html_uri"
fi

echo "Checking adb device..."
adb_devices_out="$("$ADB" devices 2>&1)" || true
if echo "$adb_devices_out" | grep -qi 'no permissions'; then
  echo "ERROR: USB device — no permissions (udev)." >&2
  echo "Xem README mục Linux (bước 3–6) hoặc linux/run_command.txt" >&2
  echo "$adb_devices_out" >&2
  exit 1
fi
if ! "$ADB" get-state >/dev/null 2>&1; then
  echo "ERROR: No adb device detected." >&2
  echo "Run: $ADB devices" >&2
  echo "$adb_devices_out" >&2
  exit 1
fi

echo "Setting log properties..."
"$ADB" shell setprop log.tag.FA VERBOSE
"$ADB" shell setprop log.tag.FA-SVC VERBOSE

read_debug_package() {
  local raw line
  raw="$("$ADB" shell getprop debug.firebase.analytics.app 2>/dev/null | tr -d '\r' || true)"
  line="$(printf '%s' "$raw" | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [[ -z "$line" || "$line" == ".none." || "$line" == "(null)" ]]; then
    return 1
  fi
  printf '%s' "$line"
}

debug_pkg="$(read_debug_package || true)"
if [[ -n "$debug_pkg" ]]; then
  export FA_DEBUG_BUNDLE="$debug_pkg"
  echo "Debug package (adb): $debug_pkg"
else
  echo "Debug package (adb): (chưa set — chạy: $ADB shell setprop debug.firebase.analytics.app <package>)"
fi

echo "Clearing old logs..."
"$ADB" logcat -c

echo "Start capturing logcat (events + user properties)..."
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
  --adb "$ADB"
  --poll-bundle-sec 2
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
if [[ -n "${FA_DEBUG_BUNDLE:-}" ]]; then
  ENGINE_CMD+=(--initial-bundle "$FA_DEBUG_BUNDLE")
fi

"$ADB" logcat -v time -s FA FA-SVC 2>/dev/null | "${ENGINE_CMD[@]}"
