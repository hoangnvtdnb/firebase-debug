#!/usr/bin/env python3
"""HTTP + SSE server cho FA viewer (Linux / fallback)."""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

VIEWER_ROOT = Path(__file__).resolve().parent
DEFAULT_STREAM = VIEWER_ROOT.parent / "linux" / "fa_logging_stream.jsonl"
DEFAULT_CONFIG = VIEWER_ROOT.parent / "linux"


def split_filter_raw(raw: str) -> list[str]:
    text = (raw or "").strip()
    if not text:
        return []
    if "\n" in text or "\r" in text:
        text = text.replace("\r\n", "\n").replace("\r", "\n")
        parts = text.split("\n")
    else:
        parts = text.split(",")
    return [p.strip() for p in parts if p.strip()]


def read_name_list(path: Path) -> list[str]:
    if not path.is_file():
        return []
    return split_filter_raw(path.read_text(encoding="utf-8"))


def write_name_list(path: Path, names: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    cleaned = [n.strip() for n in names if n and str(n).strip()]
    if any("," in n for n in cleaned):
        content = "\n".join(cleaned)
    else:
        content = ",".join(cleaned)
    tmp = path.with_name(path.name + ".tmp")
    last_err: OSError | None = None
    for attempt in range(5):
        try:
            tmp.write_text(content, encoding="utf-8")
            os.replace(tmp, path)
            return
        except OSError as e:
            last_err = e
            time.sleep(0.05 * (attempt + 1))
    if last_err:
        raise last_err


def coerce_filter_list(value) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        s = value.strip()
        return [s] if s else []
    if isinstance(value, (list, tuple)):
        return [str(x).strip() for x in value if str(x).strip()]
    s = str(value).strip()
    return [s] if s else []


def save_event_config(config_dir: Path, body: dict) -> dict:
    include = coerce_filter_list(body.get("include"))
    exclude = coerce_filter_list(body.get("exclude"))
    write_name_list(config_dir / "include_event.txt", include)
    write_name_list(config_dir / "exclude_event.txt", exclude)
    return {"include": include, "exclude": exclude}


def save_property_config(config_dir: Path, body: dict) -> dict:
    include = coerce_filter_list(body.get("include"))
    exclude = coerce_filter_list(body.get("exclude"))
    write_name_list(config_dir / "include_property.txt", include)
    write_name_list(config_dir / "exclude_property.txt", exclude)
    return {"include": include, "exclude": exclude}


def save_event_param_config(config_dir: Path, body: dict) -> dict:
    include = coerce_filter_list(body.get("include"))
    exclude = coerce_filter_list(body.get("exclude"))
    write_name_list(config_dir / "include_event_param.txt", include)
    write_name_list(config_dir / "exclude_event_param.txt", exclude)
    return {"include": include, "exclude": exclude}


def load_all_config(config_dir: Path) -> dict:
    return {
        "events": {
            "include": read_name_list(config_dir / "include_event.txt"),
            "exclude": read_name_list(config_dir / "exclude_event.txt"),
        },
        "eventParams": {
            "include": read_name_list(config_dir / "include_event_param.txt"),
            "exclude": read_name_list(config_dir / "exclude_event_param.txt"),
        },
        "properties": {
            "include": read_name_list(config_dir / "include_property.txt"),
            "exclude": read_name_list(config_dir / "exclude_property.txt"),
        },
    }


def save_all_config(config_dir: Path, body: dict) -> dict:
    return {
        "events": save_event_config(config_dir, body.get("events") or {}),
        "eventParams": save_event_param_config(config_dir, body.get("eventParams") or {}),
        "properties": save_property_config(config_dir, body.get("properties") or {}),
    }


FILTER_BUNDLE_FILE = "fa_filter_config.json"


def _bundle_section(raw: dict, key: str) -> dict:
    section = raw.get(key) if isinstance(raw.get(key), dict) else {}
    return {
        "include": coerce_filter_list(section.get("include")),
        "exclude": coerce_filter_list(section.get("exclude")),
    }


def load_filter_bundle(config_dir: Path) -> dict:
    path = config_dir / FILTER_BUNDLE_FILE
    if path.is_file():
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(raw, dict) and (
                "events" in raw or "eventParams" in raw or "properties" in raw
            ):
                return {
                    "events": _bundle_section(raw, "events"),
                    "eventParams": _bundle_section(raw, "eventParams"),
                    "properties": _bundle_section(raw, "properties"),
                }
        except (json.JSONDecodeError, OSError, TypeError):
            pass
    return load_all_config(config_dir)


def save_filter_bundle(config_dir: Path, body: dict) -> dict:
    saved = save_all_config(config_dir, body)
    bundle = {"version": 1, **saved}
    path = config_dir / FILTER_BUNDLE_FILE
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(bundle, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return saved


def load_history(stream_path: Path, max_lines: int = 10000) -> list:
    if not stream_path.is_file():
        return []
    lines = stream_path.read_text(encoding="utf-8").splitlines()
    if len(lines) > max_lines:
        lines = lines[-max_lines:]
    out = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return out


def make_handler(stream_path: Path, config_dir: Path):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass

        def route_path(self) -> str:
            return urlparse(self.path).path

        def read_post_json(self) -> dict:
            length = int(self.headers.get("Content-Length", 0) or 0)
            raw = self.rfile.read(length).decode("utf-8") if length else "{}"
            data = json.loads(raw)
            return data if isinstance(data, dict) else {}

        def write_json_response(self, status: int, payload: dict) -> None:
            body = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            path = self.route_path()
            if path == "/api/filter-config":
                self.write_json_response(200, load_filter_bundle(config_dir))
                return

            if path == "/api/config/all":
                self.write_json_response(200, load_filter_bundle(config_dir))
                return

            if path == "/api/config/events":
                body = json.dumps(
                    {
                        "include": read_name_list(config_dir / "include_event.txt"),
                        "exclude": read_name_list(config_dir / "exclude_event.txt"),
                    }
                ).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.end_headers()
                self.wfile.write(body)
                return

            if path == "/api/config/properties":
                body = json.dumps(
                    {
                        "include": read_name_list(config_dir / "include_property.txt"),
                        "exclude": read_name_list(config_dir / "exclude_property.txt"),
                    }
                ).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.end_headers()
                self.wfile.write(body)
                return

            if path in ("/api/config/event-params", "/api/config/event_params"):
                body = json.dumps(
                    {
                        "include": read_name_list(config_dir / "include_event_param.txt"),
                        "exclude": read_name_list(config_dir / "exclude_event_param.txt"),
                    }
                ).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.end_headers()
                self.wfile.write(body)
                return

            if path == "/api/history":
                body = json.dumps(load_history(stream_path)).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.end_headers()
                self.wfile.write(body)
                return

            if path == "/events":
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream; charset=utf-8")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "keep-alive")
                self.end_headers()
                self.wfile.write(b'data: {"type":"connected"}\n\n')
                self.wfile.flush()
                offset = 0
                while True:
                    if not stream_path.exists():
                        time.sleep(0.4)
                        continue
                    with stream_path.open("r", encoding="utf-8") as f:
                        size = f.seek(0, 2)
                        if size < offset:
                            offset = 0
                        f.seek(offset)
                        for line in f:
                            line = line.strip()
                            if line:
                                self.wfile.write(f"data: {line}\n\n".encode())
                                self.wfile.flush()
                        offset = f.tell()
                    time.sleep(0.3)
                return

            rel = path.lstrip("/") or "index.html"
            if ".." in rel:
                self.send_error(403)
                return
            target = VIEWER_ROOT / rel
            if not target.is_file():
                self.send_error(404)
                return
            ctype, _ = mimetypes.guess_type(str(target))
            self.send_response(200)
            self.send_header("Content-Type", ctype or "application/octet-stream")
            self.end_headers()
            self.wfile.write(target.read_bytes())

        def save_config_route(self, path: str, data: dict) -> dict:
            if path == "/api/config/events":
                return save_event_config(config_dir, data)
            if path == "/api/config/properties":
                return save_property_config(config_dir, data)
            if path in ("/api/config/event-params", "/api/config/event_params"):
                return save_event_param_config(config_dir, data)
            raise ValueError("unknown config route")

        def do_POST(self):
            path = self.route_path()
            if path == "/api/filter-config":
                try:
                    data = self.read_post_json()
                    saved = save_filter_bundle(config_dir, data)
                    self.write_json_response(200, {"ok": True, **saved})
                except (json.JSONDecodeError, TypeError, ValueError) as e:
                    self.write_json_response(400, {"error": str(e)})
                except OSError as e:
                    self.write_json_response(500, {"error": str(e)})
                return

            if path == "/api/config/all":
                try:
                    data = self.read_post_json()
                    saved = save_filter_bundle(config_dir, data)
                    self.write_json_response(200, {"ok": True, **saved})
                except (json.JSONDecodeError, TypeError, ValueError) as e:
                    self.write_json_response(400, {"error": str(e)})
                except OSError as e:
                    self.write_json_response(500, {"error": str(e)})
                return

            if path in (
                "/api/config/events",
                "/api/config/properties",
                "/api/config/event-params",
                "/api/config/event_params",
            ):
                try:
                    data = self.read_post_json()
                    saved = self.save_config_route(path, data)
                    self.write_json_response(200, {"ok": True, **saved})
                except (json.JSONDecodeError, TypeError, ValueError) as e:
                    self.write_json_response(400, {"error": str(e)})
                except OSError as e:
                    self.write_json_response(500, {"error": str(e)})
                return

            if path == "/api/clear":
                stream_path.parent.mkdir(parents=True, exist_ok=True)
                stream_path.write_text("", encoding="utf-8")
                body = json.dumps({"ok": True}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.end_headers()
                self.wfile.write(body)
                return
            self.send_error(404)

    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--stream", type=Path, default=DEFAULT_STREAM)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    args = parser.parse_args()
    args.stream.parent.mkdir(parents=True, exist_ok=True)
    if not args.stream.exists():
        args.stream.touch()

    server = ThreadingHTTPServer(
        ("127.0.0.1", args.port), make_handler(args.stream, args.config)
    )
    print(f"FA viewer: http://127.0.0.1:{args.port}/")
    print(f"Stream: {args.stream}")
    print(f"Config: {args.config}")
    server.serve_forever()


if __name__ == "__main__":
    main()
