# Firebase Analytics debug (ADB + iOS)

Ghi log Firebase Analytics từ **Android** (`adb logcat`, tag **FA** / **FA-SVC**) hoặc **iOS trên Linux** (`idevicesyslog`), lọc event & user property, xuất file text và **viewer HTML** kiểu DebugView (timeline, chi tiết params, user properties theo bundle).

**Tool by HoangData at DMOBIN GLOBAL**

---

## Yêu cầu

| Thành phần | Ghi chú |
|------------|---------|
| **Windows 10/11** | PowerShell (có sẵn) |
| **Trình duyệt** | Chrome, Edge, Firefox… |
| **Thiết bị Android** | USB debugging bật; app bật FA debug mode |
| **ADB** | Dùng bản trong `windows/adb/` hoặc `linux/adb/` — không cần cài Android Studio |
| **Python 3** | Bắt buộc trên **Linux** (capture engine + viewer) |
| **libimobiledevice** | Chỉ cho **Linux iOS** (`idevicesyslog`, `idevice_id`) |

Không cần Node.js, npm. Windows không cần Python (viewer Android = PowerShell). iOS capture chỉ có trên **linux-ios/**.

---

## Linux — iOS (idevicesyslog)

Yêu cầu: **bash**, **python3**, **libimobiledevice-utils**, iPhone cắm USB (Trust + Developer Mode trên iOS 16+).

### 1. Chuẩn bị

```bash
cd đường-dẫn/firebase-debug/linux-ios
sudo apt install -y python3 libimobiledevice-utils usbmuxd
dos2unix capture_fa_logging.sh start_fa_viewer.sh 2>/dev/null || true
chmod +x capture_fa_logging.sh start_fa_viewer.sh fa_capture_engine_ios.py
idevice_id -l   # phải thấy UDID
```

Trên app iOS (bản debug), bật trong Xcode scheme → **Arguments Passed On Launch**:

```text
-FIRDebugEnabled
-FIRAnalyticsVerboseLoggingEnabled
```

### 2. Chạy capture + viewer

```bash
./capture_fa_logging.sh --bundle com.yourcompany.yourapp
```

- Viewer: **http://127.0.0.1:8766/** (cổng **8766** để không trùng Android **8765**)
- Output: `fa_logging_results_ios.html`, `fa_logging_stream.jsonl` (thư mục `linux-ios/`)

**Tùy chọn:** `--udid`, `--no-browser`, `--fresh`, `--viewer-port`, `--no-viewer` — giống Android.

Chi tiết: `linux-ios/run_command.txt`.

---

## Chạy trên Windows (khuyến nghị)

Mở terminal tại thư mục script:

```powershell
cd đường-dẫn\tới\firebase-debug\windows
```

### Cách 1 — Chạy trực tiếp

```powershell
.\capture_fa_logging.ps1
```

### Cách 2 — Nếu bị chặn Execution Policy

```powershell
powershell -ExecutionPolicy Bypass -File .\capture_fa_logging.ps1
```

Script sẽ:

1. Mở viewer HTTP **`http://127.0.0.1:8765/`** (cập nhật live qua SSE, không reload trang)  
2. Bật log FA / FA-SVC qua ADB, `logcat -c`, rồi bắt event + user property  
3. Khi dừng capture, ghi snapshot vào **`fa_logging_results_adb.html`** (không in event ra terminal)  

Dừng capture: **Ctrl+C** trong terminal.

### Tùy chọn

```powershell
.\capture_fa_logging.ps1 -NoBrowser         # Không tự mở browser
.\capture_fa_logging.ps1 -ViewerPort 9000   # Đổi cổng viewer HTTP
.\capture_fa_logging.ps1 -NoLiveViewer      # Chỉ file HTML (F5 thủ công để cập nhật)
.\capture_fa_logging.ps1 -Fresh             # Xóa stream cũ, session mới
```

Chỉ chạy viewer (không capture):

```powershell
.\fa_viewer_server.ps1
# hoặc
powershell -ExecutionPolicy Bypass -File .\fa_viewer_server.ps1
```

### Output & session (thư mục `windows/`)

| File | Mô tả |
|------|--------|
| `fa_logging_results_adb.html` | Snapshot HTML khi **dừng** capture (hoặc cập nhật từng event nếu `-NoLiveViewer`) |
| `fa_logging_stream.jsonl` | Stream JSONL cho viewer HTTP (SSE) |
| `include_event.txt` / `exclude_event.txt` | Lọc tên event (capture + viewer) |
| `include_property.txt` / `exclude_property.txt` | Lọc user property: chỉ tên hoặc **name=value** (so khớp không phân biệt hoa thường), giống event param |
| `fa_filter_config.json` | **Ưu tiên** — toàn bộ rule lọc (events, eventParams, properties); viewer **Lưu** / **Xuất** dùng file này |
| `include_event_param.txt` / `exclude_event_param.txt` | Lọc **event parameter** (đồng bộ từ JSON khi Lưu trên viewer; capture vẫn đọc được nếu chưa có JSON) |

Trên viewer: **Lưu** → `fa_filter_config.json` + các file `.txt` (capture đọc được) qua `POST /api/filter-config`; đồng thời lưu **localStorage** trên trình duyệt. **Xuất / Nhập** file JSON khi không có viewer HTTP hoặc đồng bộ thủ công vào `firebase-debug/windows` hoặc `linux/`. Mở `http://127.0.0.1:8765/` (không mở file HTML tĩnh trực tiếp nếu cần ghi server).

### Thiết bị & debug mode

```powershell
.\adb\adb devices
```

Trên device (package app cần debug):

```text
adb shell setprop debug.firebase.analytics.app <package.name>
```

Script đọc property này để hiển thị bundle id khi có.

---

## Linux (đầy đủ như Windows)

Yêu cầu: **bash**, **python3**, **adb** (trong `linux/adb/`), thiết bị bật USB debugging.

Luồng setup đã kiểm tra trên Ubuntu/Debian — làm theo thứ tự sau.

### 1. Chuẩn bị (một lần)

```bash
sudo apt install -y python3 dos2unix   # python3 bắt buộc cho capture + viewer
dos2unix capture_fa_logging.sh start_fa_viewer.sh 2>/dev/null || true
chmod +x capture_fa_logging.sh start_fa_viewer.sh fa_capture_engine.py adb/adb
```

> Clone từ Windows: `dos2unix` tránh lỗi `\r` khi chạy `.sh`.

### 2. Chạy capture + viewer

```bash
./capture_fa_logging.sh
```

- Viewer: **http://127.0.0.1:8765/** (tự mở browser nếu có `xdg-open`)
- Dừng capture: **Ctrl+C**
- Output: `fa_logging_results_adb.html` (snapshot viewer), `fa_logging_results_adb.txt` (log text), `fa_logging_stream.jsonl` (cùng thư mục `linux/`)

**Tùy chọn:**

```bash
./capture_fa_logging.sh --no-viewer          # Chỉ terminal + file text
./capture_fa_logging.sh --no-live-viewer     # Chỉ HTML (F5 cập nhật), không viewer HTTP
./capture_fa_logging.sh --no-browser
./capture_fa_logging.sh --viewer-port 9000
./capture_fa_logging.sh --fresh              # Xóa stream cũ, session mới
```

**Chỉ viewer** (không capture):

```bash
./start_fa_viewer.sh
# cổng khác: ./start_fa_viewer.sh 9000
```

Cấu hình lọc (`include_event.txt`, `exclude_event.txt`, …) và UI viewer giống Windows.

### Output & session (thư mục `linux/`)

| File | Mô tả |
|------|--------|
| `fa_logging_results_adb.html` | Snapshot HTML khi **dừng** capture (hoặc cập nhật từng event nếu `--no-live-viewer`) |
| `fa_logging_results_adb.txt` | Log text (terminal + file) |
| `fa_logging_stream.jsonl` | Stream JSONL cho viewer HTTP (SSE) |
| `include_event.txt` / `exclude_event.txt` | Lọc tên event |
| `include_property.txt` / `exclude_property.txt` | Lọc user property: chỉ tên hoặc **name=value** (so khớp không phân biệt hoa thường) |

Viewer dùng chung `viewer/`: tối đa **10.000 events**; timeline **user_property** giữ lịch sử mỗi lần set — khi events đầy 10k thì timeline property chỉ còn **bản mới nhất** mỗi tên (panel bundle vẫn hiện giá trị mới nhất).

### 3–6. Nếu lỗi `no permissions` (udev USB)

Khi `./adb/adb devices` hiện `no permissions`, cấu hình udev (thay `22d9` bằng **idVendor** của máy bạn):

**3.** Lấy vendor ID:

```bash
lsusb
# Ví dụ: Bus 001 Device 007: ID 22d9:2769 OPPO ...  → idVendor = 22d9
```

**4.** Thêm rule:

```bash
sudo nano /etc/udev/rules.d/51-android.rules
```

Thêm một dòng (đổi `22d9` cho đúng):

```text
SUBSYSTEM=="usb", ATTR{idVendor}=="22d9", MODE="0666", GROUP="plugdev"
```

**5.** Áp dụng rule:

```bash
sudo chmod a+r /etc/udev/rules.d/51-android.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo service udev restart
```

**6.** Tháo USB, cắm lại, kiểm tra:

```bash
./adb/adb kill-server
./adb/adb start-server
./adb/adb devices
```

Trạng thái hợp lệ: `XXXXXXXX    device` (không phải `unauthorized` / `no permissions`).

Sau đó chạy lại `./capture_fa_logging.sh`.

Chi tiết copy-paste: `linux/run_command.txt`.

### Thiết bị & debug mode (Linux)

Bundle id lấy từ log `Event{appId=...}` / `App package...` và từ:

```bash
./adb/adb shell setprop debug.firebase.analytics.app <package.name>
```

Bundle id được gán **theo từng event** từ log FA-SVC: ngay trước mỗi `Logging event:` luôn có dòng `... appId: <package>` và `EES (not )loaded for: <package>` (cùng luồng GMS nối tiếp), nên gán đúng app kể cả khi **debug nhiều app cùng lúc** và swap qua lại. `debug.firebase.analytics.app` (getprop) chỉ dùng làm **seed ban đầu** khi chưa có event nào.

> Lưu ý: tag `FA-SVC` chạy trong tiến trình Google Play Services dùng chung cho mọi app, nên KHÔNG thể map theo PID hay app foreground — phải đọc `appId:` trong nội dung log.

Kiểm tra:

```bash
./adb/adb shell getprop debug.firebase.analytics.app
```

---

## Dữ liệu có bị mất khi tắt shell?

Viewer live lưu session trên **disk** (`fa_logging_stream.jsonl`), không chỉ trong RAM trình duyệt.

| Hành động | Kết quả |
|-----------|---------|
| **F5 / mở lại tab** viewer | Tải lại từ `fa_logging_stream.jsonl` (nếu viewer HTTP vẫn chạy) |
| **Ctrl+C** hoặc đóng shell capture | Ghi snapshot `fa_logging_results_adb.html` (mở file này xem offline) |
| **Chạy lại capture** | Mặc định **giữ** stream cũ; dùng `-Fresh` / `--fresh` nếu muốn session mới |
| **Nút CLEAR** trên viewer | Xóa stream + UI (chỉ live viewer) |

**Lưu ý:** Tab browser đang mở vẫn giữ data trong RAM — **F5 sau khi tắt shell** cần viewer server còn chạy. Trên Linux viewer được `nohup` (sống sau khi đóng terminal capture). Trên Windows viewer chạy process riêng (`fa_viewer_server.ps1`).

Nếu viewer không còn chạy: mở `fa_logging_results_adb.html` hoặc chạy lại `./start_fa_viewer.sh` / `fa_viewer_server.ps1` rồi F5.

---

## Tech stack (tóm tắt)

| Lớp | Công nghệ |
|-----|-----------|
| Capture | PowerShell (Windows) / Bash + `fa_capture_engine.py` (Linux) + `adb logcat` |
| Server viewer (Windows) | PowerShell + `HttpListener`, SSE |
| Server viewer (Linux) | Python 3 `ThreadingHTTPServer` (`viewer/serve.py`), SSE |
| UI | HTML, CSS, JavaScript thuần |

---

## Cấu trúc thư mục

```text
firebase-debug/
  README.md
  .gitignore               # bỏ adb/, file runtime, __pycache__…
  .gitattributes           # chuẩn hóa line-ending (ps1=CRLF, sh=LF)
  viewer/              # index.html, index_ios.html, app.js, serve.py
  windows/
    capture_fa_logging.ps1   # ← entry point Windows (Android)
    fa_viewer_server.ps1
    start_fa_viewer.ps1
    adb/                     # adb.exe — TẢI RIÊNG (gitignore)
  linux/
    capture_fa_logging.sh    # ← entry point Linux Android
    fa_capture_engine.py
    fa_bundle_track.py
    fa_html_export.py
    fa_record_store.py
    start_fa_viewer.sh
    adb/                     # adb — TẢI RIÊNG (gitignore)
  linux-ios/
    capture_fa_logging.sh    # ← entry point Linux iOS
    fa_capture_engine_ios.py
    start_fa_viewer.sh       # viewer cổng 8766
    include_event.txt
    exclude_event.txt
```

---

## Sang máy khác

Copy hoặc clone cả thư mục `firebase-debug`, cắm thiết bị Android:

- **Windows:** [Chạy trên Windows](#chạy-trên-windows-khuyến-nghị)  
- **Linux:** [bước 1–2](#1-chuẩn-bị-một-lần); nếu ADB báo `no permissions` → [bước 3–6](#3-6-nếu-lỗi-no-permissions-udev-usb)

Không cần Node/npm. Linux cần `python3` + (một lần) `dos2unix` nếu file `.sh` từ Windows.

---

## Cài đặt adb (platform-tools)

Thư mục `windows/adb/` và `linux/adb/` **không được commit vào git** (xem `.gitignore`) vì nặng (~30MB) và là binary của Google. Sau khi clone repo, tải platform-tools và đặt vào đúng vị trí:

1. Tải **SDK Platform-Tools** của Google:
   - Windows: <https://dl.google.com/android/repository/platform-tools-latest-windows.zip>
   - Linux: <https://dl.google.com/android/repository/platform-tools-latest-linux.zip>
2. Giải nén, copy nội dung thư mục `platform-tools/` vào:
   - **Windows** → `firebase-debug/windows/adb/` (phải có `adb.exe`)
   - **Linux** → `firebase-debug/linux/adb/` (phải có `adb`, rồi `chmod +x adb/adb`)
3. Kiểm tra: `./adb/adb devices` (Linux) hoặc `.\adb\adb devices` (Windows).

> Nếu muốn **bundle adb vào repo** cho tiện (không cần tải lại), mở `.gitignore` và xóa/comment 2 dòng `linux/adb/` + `windows/adb/`.

---

## Tạo git repo riêng

Phần `firebase-debug` đang nằm trong repo `dfinance`. Để tách thành repo độc lập:

```bash
cd firebase-debug

# 1. Khởi tạo repo mới (repo này đã có sẵn .gitignore + .gitattributes)
git init
git add .
git commit -m "Initial commit: Firebase Analytics debug tool (ADB)"

# 2. Tạo repo rỗng trên GitHub rồi push
git remote add origin git@github.com:<user>/firebase-debug.git
git branch -M main
git push -u origin main
```

Kiểm tra trước khi commit để chắc adb / file runtime **không** bị thêm vào:

```bash
git status            # adb/, *.jsonl, __pycache__ ... phải nằm ngoài danh sách
git check-ignore -v windows/adb/adb.exe linux/adb/adb
```

> Nếu trước đó các file này đã bị track (do clone từ repo cũ), gỡ khỏi index nhưng giữ file trên đĩa:
>
> ```bash
> git rm -r --cached windows/adb linux/adb
> git rm --cached windows/fa_logging_stream.jsonl 2>/dev/null
> git commit -m "Stop tracking adb binaries & runtime files"
> ```
