#!/usr/bin/env python3
"""Parse idevicesyslog (iOS Firebase Analytics) → text log + JSONL (parity with linux/ Android)."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

_LINUX = Path(__file__).resolve().parent.parent / "linux"
if str(_LINUX) not in sys.path:
    sys.path.insert(0, str(_LINUX))

from fa_capture_engine import (  # noqa: E402
    format_bundle_tag,
    infer_value_type,
    load_filter_bundle,
    read_name_list,
    test_event_param_filter,
    test_name_filter,
    test_property_filter,
    to_json_event,
    to_json_property,
)
from fa_html_export import write_fa_logging_html  # noqa: E402
from fa_record_store import FaRecordStore  # noqa: E402

SKIP_PARAM_KEYS = frozenset(
    {
        "ga_event_origin(_o)",
        "ga_screen_class(_sc)",
        "ga_screen_id(_si)",
        "firebase_event_origin(_o)",
        "firebase_screen_class(_sc)",
        "firebase_screen_id(_si)",
        "_o",
    }
)

RE_TS_FULL = re.compile(
    r"(?P<ts>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)"
)
RE_TS_SYSLOG = re.compile(
    r"(?P<ts>\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)"
)
RE_TS_SHORT = re.compile(r"(?P<ts>\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3})")
RE_IOS_EVENT = re.compile(
    r"Logging event:\s*(?P<origin>[^,]+),\s*(?P<name>[^,]+),\s*params:",
    re.IGNORECASE,
)
RE_IOS_USER_PROP = re.compile(
    r"Setting user property\.?\s*Name, value:\s*(?P<name>[^,]+),\s*(?P<value>.+?)\s*$",
    re.IGNORECASE,
)
RE_BUNDLE_IN_LINE = re.compile(
    r"(?:CFBundleIdentifier|bundle[_\s-]?id)['\"]?\s*[:=]\s*['\"]?"
    r"(?P<id>[a-zA-Z][a-zA-Z0-9._-]+)",
    re.IGNORECASE,
)
RE_PROCESS_BUNDLE = re.compile(
    r"\b(?P<id>[a-zA-Z][a-zA-Z0-9._-]+)\[(?:\d+|pid)\]",
)


def extract_timestamp(line: str) -> str:
    for pat in (RE_TS_FULL, RE_TS_SHORT, RE_TS_SYSLOG):
        m = pat.search(line)
        if m:
            return m.group("ts")
    return ""


def normalize_log_line(line: str) -> str:
    return line.strip()


def is_fa_line(line: str) -> bool:
    low = line.lower()
    if "logging event:" in low or "setting user property" in low:
        return True
    return "firebase/analytics" in low or "firanalytics" in low


def extract_brace_content(line: str) -> str:
    start = line.find("{")
    if start < 0:
        return ""
    depth = 0
    for i in range(start, len(line)):
        ch = line[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return line[start + 1 : i]
    return ""


def parse_ios_params(dict_body: str) -> dict:
    """NSDictionary-style: key = value; hoặc \"key\" = \"value\"."""
    params: dict = {}
    if not dict_body or not dict_body.strip():
        return params
    body = dict_body.strip()
    parts = re.split(r"[;,]\s*", body)
    for part in parts:
        part = part.strip()
        if not part:
            continue
        m = re.match(
            r'^(?:"([^"]+)"|([^"=]+))\s*=\s*(?:"([^"]*)"|(.+))$',
            part,
        )
        if not m:
            continue
        key = (m.group(1) or m.group(2) or "").strip()
        val = (m.group(3) if m.group(3) is not None else m.group(4) or "").strip()
        if not key or key in SKIP_PARAM_KEYS:
            continue
        params[key] = {"value": val, "valueType": infer_value_type(val)}
    return params


class FaIosCaptureState:
    def __init__(self, initial_bundle: str = "") -> None:
        self.bundle_context = (initial_bundle or "").strip()

    def set_bundle(self, bundle_id: str) -> None:
        bid = (bundle_id or "").strip()
        if bid:
            self.bundle_context = bid

    def get_bundle(self) -> str:
        return self.bundle_context

    def update_bundle_from_line(self, line: str) -> None:
        m = RE_BUNDLE_IN_LINE.search(line)
        if m:
            self.set_bundle(m.group("id"))
            return
        m = RE_PROCESS_BUNDLE.search(line)
        if m and "." in m.group("id"):
            self.set_bundle(m.group("id"))

    def parse_event(self, line: str):
        m = RE_IOS_EVENT.search(line)
        if not m:
            return None
        name = m.group("name").strip()
        ts = extract_timestamp(line) or ""
        dict_body = extract_brace_content(line)
        params = parse_ios_params(dict_body)
        return {
            "ts": ts,
            "name": name,
            "bundleId": self.get_bundle(),
            "params": params,
        }

    def parse_user_property(self, line: str):
        if "user property set" in line.lower():
            return None
        m = RE_IOS_USER_PROP.search(line)
        if not m:
            return None
        val = m.group("value").strip()
        if val.endswith("]") and "[" in val:
            val = val.rsplit("[", 1)[0].strip()
        return {
            "ts": extract_timestamp(line) or "",
            "name": m.group("name").strip(),
            "value": val,
            "valueType": infer_value_type(val),
            "bundleId": self.get_bundle(),
        }


def format_event_text(event: dict) -> str:
    tag = format_bundle_tag(event.get("bundleId", ""))
    ts = event.get("ts") or "—"
    lines = [f"{ts}  {tag}event: {event['name']}"]
    for key, entry in event.get("params", {}).items():
        lines.append(f"  {key} = {entry['value']} ({entry['valueType']})")
    return "\n".join(lines) + "\n"


def format_property_text(prop: dict) -> str:
    tag = format_bundle_tag(prop.get("bundleId", ""))
    ts = prop.get("ts") or "—"
    return (
        f"{ts}  {tag}user_property: {prop['name']} = {prop['value']}\n"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--stream", type=Path, required=True)
    parser.add_argument("--config-dir", type=Path, required=True)
    parser.add_argument("--write-stream", action="store_true")
    parser.add_argument("--initial-bundle", default="")
    parser.add_argument("--html-output", type=Path, default=None)
    parser.add_argument("--viewer-index", type=Path, default=None)
    parser.add_argument("--viewer-rel", default="../viewer")
    parser.add_argument("--incremental-html", action="store_true")
    parser.add_argument("--init-html-only", action="store_true")
    parser.add_argument(
        "--require-fa-subsystem",
        action="store_true",
        default=True,
        help="Bỏ qua dòng không liên quan Firebase Analytics (mặc định bật)",
    )
    parser.add_argument(
        "--no-require-fa-subsystem",
        action="store_false",
        dest="require_fa_subsystem",
    )
    args = parser.parse_args()

    cfg = args.config_dir
    bundle = load_filter_bundle(cfg)
    if bundle:
        include_events = [
            str(x).strip() for x in bundle["events"]["include"] if str(x).strip()
        ]
        exclude_events = [
            str(x).strip() for x in bundle["events"]["exclude"] if str(x).strip()
        ]
        include_props = [
            str(x).strip() for x in bundle["properties"]["include"] if str(x).strip()
        ]
        exclude_props = [
            str(x).strip() for x in bundle["properties"]["exclude"] if str(x).strip()
        ]
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
        viewer_index = cfg.parent.parent / "viewer" / "index_ios.html"
        if not viewer_index.is_file():
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

    state = FaIosCaptureState(args.initial_bundle)

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
            if args.require_fa_subsystem and not is_fa_line(line):
                continue
            state.update_bundle_from_line(line)

            low = line.lower()
            is_event = "logging event:" in low
            is_prop = "setting user property" in low
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
                    parsed.get("params") or {},
                    include_event_params,
                    exclude_event_params,
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
        pass
    finally:
        try:
            out_fp.close()
        except OSError:
            pass
        try:
            write_html_snapshot()
        except Exception as e:  # noqa: BLE001
            sys.stderr.write(f"\n[fa_capture_ios] Bỏ qua lỗi ghi HTML khi thoát: {e}\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)
