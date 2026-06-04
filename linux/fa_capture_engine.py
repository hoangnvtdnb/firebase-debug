#!/usr/bin/env python3
"""Parse adb logcat FA lines → text log + JSONL (parity with Windows capture)."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import threading
from pathlib import Path

from fa_html_export import write_fa_logging_html
from fa_record_store import FaRecordStore

SKIP_PARAM_KEYS = frozenset(
    {
        "ga_event_origin(_o)",
        "ga_screen_class(_sc)",
        "ga_screen_id(_si)",
        "firebase_event_origin(_o)",
        "firebase_screen_class(_sc)",
        "firebase_screen_id(_si)",
    }
)

# MM-DD or YYYY-MM-DD (một số bản adb logcat trên Linux có năm 4 chữ số)
RE_TS = r"(?P<ts>(?:\d{4}-)?\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3})"
RE_EVENT = re.compile(
    rf"^{RE_TS}.*?Logging event:.*?name=(?P<name>[^,]+)",
    re.DOTALL,
)
RE_PARAMS = re.compile(r"params=Bundle\[\{(?P<params>.*)\}\]")
RE_USER_PROP = re.compile(
    rf"^{RE_TS}.*?Setting user property(?:\s*\([^)]*\))?:\s*(?P<name>[^,]+),\s*(?P<value>.+)$",
    re.DOTALL,
)
RE_EVENT_RECORDED_APPID = re.compile(
    r"Event(?:\s+recorded)?:\s*Event\{[^}]*appId=['\"]?(?P<id>[^'\",}\s]+)",
    re.IGNORECASE,
)
RE_APPID_QUOTED = re.compile(r"appId=['\"](?P<id>[^'\"]+)['\"]")
RE_APPID_BARE = re.compile(r"(?<![a-zA-Z_])appId=(?P<id>[a-zA-Z][a-zA-Z0-9._]*)")
# FA-SVC (tiến trình GMS dùng chung) log dạng `appId: com.foo` (hai chấm) ngay trước
# mỗi `Logging event:` — đây là tín hiệu đáng tin để gán bundle khi debug nhiều app.
RE_APPID_COLON = re.compile(r"(?<![a-zA-Z_])appId:\s*(?P<id>[a-zA-Z][a-zA-Z0-9._]+)")
RE_EES_FOR = re.compile(
    r"EES (?:not )?loaded for:\s*(?P<id>[a-zA-Z][a-zA-Z0-9._]+)",
    re.IGNORECASE,
)
RE_APP_PACKAGE = re.compile(
    r"App package, google app id:\s*(?P<id>[a-zA-Z][a-zA-Z0-9._]*)",
    re.IGNORECASE,
)
RE_GOOGLE_APP_ID = re.compile(
    r"google app id(?:\s+is)?:\s*(?P<id>[a-zA-Z][a-zA-Z0-9._]*)",
    re.IGNORECASE,
)


def read_name_list(path: Path) -> list[str]:
    if not path.is_file():
        return []
    raw = path.read_text(encoding="utf-8").strip()
    if not raw:
        return []
    if "\n" in raw or "\r" in raw:
        raw = raw.replace("\r\n", "\n").replace("\r", "\n")
        parts = raw.split("\n")
    else:
        parts = raw.split(",")
    return [p.strip() for p in parts if p.strip()]


def load_filter_bundle(cfg: Path) -> dict | None:
    path = cfg / "fa_filter_config.json"
    if not path.is_file():
        return None
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None
    if not isinstance(raw, dict):
        return None

    def section(key: str) -> dict:
        block = raw.get(key) if isinstance(raw.get(key), dict) else {}
        inc = block.get("include", [])
        exc = block.get("exclude", [])
        return {
            "include": inc if isinstance(inc, list) else ([str(inc)] if inc else []),
            "exclude": exc if isinstance(exc, list) else ([str(exc)] if exc else []),
        }

    return {
        "events": section("events"),
        "eventParams": section("eventParams"),
        "properties": section("properties"),
    }


def normalize_log_line(line: str) -> str:
    """Bỏ prefix rác; hỗ trợ logcat có năm 4 chữ số."""
    line = line.strip()
    if not line:
        return line
    m = re.search(RE_TS, line)
    if m and m.start() > 0:
        return line[m.start() :]
    return line


def read_adb_debug_package(adb: Path) -> str:
    try:
        r = subprocess.run(
            [str(adb), "shell", "getprop", "debug.firebase.analytics.app"],
            capture_output=True,
            text=True,
            timeout=8,
        )
        if r.returncode != 0:
            return ""
        raw = (r.stdout or "").replace("\r", "\n").strip()
        if not raw:
            return ""
        line = raw.split("\n", 1)[0].strip()
        if line.startswith("[") and "]" in line:
            line = line.split("]", 1)[-1].strip()
        if line in ("", ".none.", "(null)"):
            return ""
        return line
    except (OSError, subprocess.TimeoutExpired):
        return ""


def infer_value_type(value: str) -> str:
    s = value.strip()
    if not s:
        return "string"
    if s in ("true", "false"):
        return "boolean"
    if s == "null":
        return "null"
    if re.fullmatch(r"-?\d+", s):
        return "int"
    if re.fullmatch(r"-?(?:\d+\.\d*|\.\d+)(?:[eE][+-]?\d+)?$", s) or re.fullmatch(
        r"-?\d+[eE][+-]?\d+$", s
    ):
        return "double"
    return "string"


def test_name_filter(name: str, include: list[str], exclude: list[str]) -> bool:
    if include and name not in include:
        return False
    if exclude and name in exclude:
        return False
    return True


def parse_param_filter_rule(raw: str) -> tuple[str, str | None]:
    s = (raw or "").strip()
    if "=" not in s:
        return s, None
    name, _, value = s.partition("=")
    name = name.strip()
    value = value.strip()
    if not value:
        return name, None
    return name, value


def _param_entry_value(entry) -> str:
    if isinstance(entry, dict):
        return str(entry.get("value", ""))
    return str(entry)


def _event_matches_param_rule(params: dict, rule_raw: str) -> bool:
    name, want = parse_param_filter_rule(rule_raw)
    if not name or not params or name not in params:
        return False
    if want is None:
        return True
    actual = _param_entry_value(params[name])
    return actual.strip().lower() == want.strip().lower()


def test_event_param_filter(params: dict, include: list[str], exclude: list[str]) -> bool:
    if include and not any(_event_matches_param_rule(params, r) for r in include):
        return False
    if exclude and any(_event_matches_param_rule(params, r) for r in exclude):
        return False
    return True


def _property_matches_rule(name: str, value: str, rule_raw: str) -> bool:
    rule_name, want = parse_param_filter_rule(rule_raw)
    if not rule_name or name != rule_name:
        return False
    if want is None:
        return True
    return str(value).strip().lower() == want.strip().lower()


def test_property_filter(name: str, value: str, include: list[str], exclude: list[str]) -> bool:
    if include and not any(_property_matches_rule(name, value, r) for r in include):
        return False
    if exclude and any(_property_matches_rule(name, value, r) for r in exclude):
        return False
    return True


class FaCaptureState:
    def __init__(self) -> None:
        self.bundle_context = ""
        self._lock = threading.Lock()

    def set_bundle(self, bundle_id: str) -> None:
        bid = (bundle_id or "").strip()
        if not bid or bid in (".none.", "(null)"):
            return
        with self._lock:
            self.bundle_context = bid

    def get_bundle(self) -> str:
        with self._lock:
            return self.bundle_context

    def update_bundle_from_line(self, line: str) -> None:
        for pat in (
            RE_EVENT_RECORDED_APPID,
            RE_APPID_COLON,
            RE_EES_FOR,
            RE_APP_PACKAGE,
            RE_GOOGLE_APP_ID,
            RE_APPID_QUOTED,
        ):
            m = pat.search(line)
            if m:
                self.set_bundle(m.group("id"))
                return

        # appId= không có quote: tránh nhầm trong params=Bundle[{...}]
        if "params=Bundle" in line:
            head = line.split("params=Bundle", 1)[0]
        else:
            head = line
        if (
            "Logging event:" in line
            or "Event{" in line
            or "Event recorded" in line
            or "Setting user property" in line
            or "App package" in line
        ):
            search_in = line if ("Event{" in line or "Event recorded" in line) else head
            m = RE_APPID_BARE.search(search_in)
            if m:
                self.set_bundle(m.group("id"))

    def bundle_for_line(self, line: str) -> str:
        for pat in (RE_EVENT_RECORDED_APPID, RE_APPID_QUOTED, RE_APPID_BARE):
            m = pat.search(line)
            if m:
                return m.group("id").strip()
        return self.get_bundle()

    def parse_event(self, line: str):
        m = RE_EVENT.match(line)
        if not m:
            return None
        ts = m.group("ts")
        name = m.group("name").strip()
        params_raw = ""
        pm = RE_PARAMS.search(line)
        if pm:
            params_raw = pm.group("params")
        params = {}
        if params_raw:
            for pair in re.split(r",\s*", params_raw):
                eq = pair.find("=")
                if eq < 1:
                    continue
                key = pair[:eq].strip()
                val = pair[eq + 1 :].strip()
                if key in SKIP_PARAM_KEYS:
                    continue
                params[key] = {"value": val, "valueType": infer_value_type(val)}
        return {
            "ts": ts,
            "name": name,
            "bundleId": self.bundle_for_line(line),
            "params": params,
        }

    def parse_user_property(self, line: str):
        m = RE_USER_PROP.match(line)
        if not m:
            return None
        val = m.group("value").strip()
        return {
            "ts": m.group("ts"),
            "name": m.group("name").strip(),
            "value": val,
            "valueType": infer_value_type(val),
            "bundleId": self.bundle_for_line(line),
        }


def format_bundle_tag(bundle_id: str) -> str:
    if not bundle_id or not bundle_id.strip():
        return ""
    return f"[{bundle_id}] "


def format_event_text(event: dict) -> str:
    tag = format_bundle_tag(event.get("bundleId", ""))
    lines = [f"{event['ts']}  {tag}event: {event['name']}"]
    for key, entry in event.get("params", {}).items():
        lines.append(f"  {key} = {entry['value']} ({entry['valueType']})")
    return "\n".join(lines) + "\n"


def format_property_text(prop: dict) -> str:
    tag = format_bundle_tag(prop.get("bundleId", ""))
    return (
        f"{prop['ts']}  {tag}user_property: {prop['name']} = {prop['value']}\n"
    )


def to_json_event(event: dict) -> dict:
    return {
        "type": "event",
        "ts": event["ts"],
        "name": event["name"],
        "bundleId": event.get("bundleId", ""),
        "params": event.get("params", {}),
    }


def to_json_property(prop: dict) -> dict:
    return {
        "type": "user_property",
        "ts": prop["ts"],
        "name": prop["name"],
        "bundleId": prop.get("bundleId", ""),
        "value": prop["value"],
        "valueType": prop["valueType"],
    }


def start_bundle_poll(adb: Path, state: FaCaptureState, interval_sec: float = 5.0):
    stop = threading.Event()

    def worker() -> None:
        while not stop.wait(interval_sec):
            # Chỉ seed khi chưa có bundle nào; KHÔNG ghi đè context đang bám theo
            # luồng log (tránh gán nhầm cho event của app chạy nền).
            if state.get_bundle():
                stop.set()
                return
            pkg = read_adb_debug_package(adb)
            if pkg:
                state.set_bundle(pkg)

    t = threading.Thread(target=worker, name="fa-bundle-poll", daemon=True)
    t.start()
    return stop


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--stream", type=Path, required=True)
    parser.add_argument("--config-dir", type=Path, required=True)
    parser.add_argument(
        "--write-stream",
        action="store_true",
        help="Append JSON lines for viewer",
    )
    parser.add_argument(
        "--initial-bundle",
        default="",
        help="debug.firebase.analytics.app from adb getprop",
    )
    parser.add_argument(
        "--adb",
        type=Path,
        default=None,
        help="Path to adb binary for getprop polling",
    )
    parser.add_argument(
        "--poll-bundle-sec",
        type=float,
        default=5.0,
        help="Seed bundle từ getprop khi chưa có context (giây, 0=tắt). "
        "Bundle chính lấy từ log appId:/EES for: trong luồng FA-SVC.",
    )
    parser.add_argument(
        "--html-output",
        type=Path,
        default=None,
        help="Ghi snapshot HTML viewer khi dừng capture",
    )
    parser.add_argument(
        "--viewer-index",
        type=Path,
        default=None,
        help="Đường dẫn viewer/index.html",
    )
    parser.add_argument(
        "--viewer-rel",
        default="../viewer",
        help="Relative path từ HTML output tới viewer assets",
    )
    parser.add_argument(
        "--incremental-html",
        action="store_true",
        help="Cập nhật HTML sau mỗi bản ghi (--no-live-viewer)",
    )
    parser.add_argument(
        "--init-html-only",
        action="store_true",
        help="Ghi HTML rỗng rồi thoát (khởi tạo trước khi capture)",
    )
    args = parser.parse_args()

    cfg = args.config_dir
    bundle = load_filter_bundle(cfg)
    if bundle:
        include_events = [str(x).strip() for x in bundle["events"]["include"] if str(x).strip()]
        exclude_events = [str(x).strip() for x in bundle["events"]["exclude"] if str(x).strip()]
        include_props = [str(x).strip() for x in bundle["properties"]["include"] if str(x).strip()]
        exclude_props = [str(x).strip() for x in bundle["properties"]["exclude"] if str(x).strip()]
        include_event_params = [
            str(x).strip() for x in bundle["eventParams"]["include"] if str(x).strip()
        ]
        exclude_event_params = [
            str(x).strip() for x in bundle["eventParams"]["exclude"] if str(x).strip()
        ]
    else:
        include_events = read_name_list(cfg / "include_event.txt")
        exclude_events = read_name_list(cfg / "exclude_event.txt")
        include_props = read_name_list(cfg / "include_property.txt")
        exclude_props = read_name_list(cfg / "exclude_property.txt")
        include_event_params = read_name_list(cfg / "include_event_param.txt")
        exclude_event_params = read_name_list(cfg / "exclude_event_param.txt")

    filter_config = {
        "events": {"include": include_events, "exclude": exclude_events},
        "eventParams": {
            "include": include_event_params,
            "exclude": exclude_event_params,
        },
        "properties": {"include": include_props, "exclude": exclude_props},
    }

    store = FaRecordStore()
    viewer_index = args.viewer_index
    if args.html_output and not viewer_index:
        viewer_index = cfg.parent.parent / "viewer" / "index.html"

    def write_html_snapshot() -> None:
        if not args.html_output or not viewer_index or not viewer_index.is_file():
            return
        write_fa_logging_html(
            output_path=args.html_output,
            viewer_index=viewer_index,
            viewer_rel=args.viewer_rel,
            events=store.events,
            properties=store.properties,
            property_latest=store.property_latest,
            filter_config=filter_config,
        )

    if args.incremental_html and args.html_output:
        write_html_snapshot()

    if args.init_html_only:
        write_html_snapshot()
        return 0

    state = FaCaptureState()
    if args.initial_bundle and args.initial_bundle.strip() not in ("", ".none.", "(null)"):
        state.set_bundle(args.initial_bundle)

    adb_path = args.adb
    if adb_path and adb_path.is_file():
        if not state.get_bundle():
            pkg = read_adb_debug_package(adb_path)
            if pkg:
                state.set_bundle(pkg)
        if args.poll_bundle_sec > 0:
            start_bundle_poll(adb_path, state, args.poll_bundle_sec)

    out_fp = args.output.open("a", encoding="utf-8")
    stream_path = args.stream

    def write_stream(record: dict) -> None:
        if not args.write_stream:
            return
        with stream_path.open("a", encoding="utf-8") as sf:
            sf.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")))
            sf.write("\n")
            sf.flush()

    def emit_record(record: dict, text: str) -> None:
        store.add_record(record)
        write_stream(record)
        sys.stdout.write(text)
        sys.stdout.flush()
        out_fp.write(text)
        out_fp.flush()
        if args.incremental_html:
            write_html_snapshot()

    try:
        for raw in sys.stdin:
            line = normalize_log_line(raw)
            if not line:
                continue
            state.update_bundle_from_line(line)

            is_event = "Logging event:" in line
            is_prop = "Setting user property" in line
            if not is_event and not is_prop:
                continue

            if is_event:
                parsed = state.parse_event(line)
                if not parsed:
                    continue
                if not test_name_filter(
                    parsed["name"], include_events, exclude_events
                ):
                    continue
                if not test_event_param_filter(
                    parsed.get("params") or {}, include_event_params, exclude_event_params
                ):
                    continue
                record = to_json_event(parsed)
                emit_record(record, format_event_text(parsed))
            else:
                parsed = state.parse_user_property(line)
                if not parsed:
                    continue
                if not test_property_filter(
                    parsed["name"],
                    parsed.get("value", ""),
                    include_props,
                    exclude_props,
                ):
                    continue
                record = to_json_property(parsed)
                emit_record(record, format_property_text(parsed))
    except KeyboardInterrupt:
        # Ctrl+C: dừng capture êm, không in traceback
        pass
    finally:
        try:
            out_fp.close()
        except OSError:
            pass
        try:
            write_html_snapshot()
        except Exception as e:  # noqa: BLE001 - tránh traceback khi đang thoát
            sys.stderr.write(f"\n[fa_capture] Bỏ qua lỗi ghi HTML khi thoát: {e}\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)
