#!/usr/bin/env python3
"""Cấu hình tracking bundle qua adb setprop debug.firebase.analytics.app."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

BUNDLE_TRACK_FILE = "fa_bundle_track.json"
MODE_ALL = "all"
MODE_SINGLE = "single"
PROP_NONE = ".none."
MAX_BUNDLE_HISTORY = 30


def default_bundle_track() -> dict:
    return {"mode": MODE_ALL, "package": "", "history": []}


def normalize_bundle_history(raw) -> list[str]:
    if not isinstance(raw, list):
        return []
    out: list[str] = []
    seen: set[str] = set()
    for item in raw:
        s = str(item or "").strip()
        if not s or s in (PROP_NONE, "(null)") or s in seen:
            continue
        seen.add(s)
        out.append(s)
        if len(out) >= MAX_BUNDLE_HISTORY:
            break
    return out


def load_bundle_track(config_dir: Path) -> dict:
    path = config_dir / BUNDLE_TRACK_FILE
    if not path.is_file():
        return default_bundle_track()
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return default_bundle_track()
    if not isinstance(raw, dict):
        return default_bundle_track()
    mode = str(raw.get("mode") or MODE_ALL).strip().lower()
    if mode not in (MODE_ALL, MODE_SINGLE):
        mode = MODE_ALL
    package = str(raw.get("package") or "").strip()
    if mode == MODE_SINGLE and not package:
        mode = MODE_ALL
        package = ""
    history = normalize_bundle_history(raw.get("history"))
    return {"mode": mode, "package": package, "history": history}


def save_bundle_track(config_dir: Path, mode: str, package: str = "") -> dict:
    mode = str(mode or MODE_ALL).strip().lower()
    package = str(package or "").strip()
    if mode not in (MODE_ALL, MODE_SINGLE):
        mode = MODE_ALL
    if mode == MODE_SINGLE:
        if not package or package in (PROP_NONE, "(null)"):
            raise ValueError("Cần package name khi tracking một bundle.")
    else:
        package = ""
    prev = load_bundle_track(config_dir)
    history = list(prev.get("history") or [])
    if mode == MODE_SINGLE and package:
        history = [package] + [h for h in history if h != package]
    history = history[:MAX_BUNDLE_HISTORY]
    cfg = {"mode": mode, "package": package, "history": history}
    path = config_dir / BUNDLE_TRACK_FILE
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return cfg


def read_adb_debug_app(adb: Path) -> str:
    if not adb or not adb.is_file():
        return ""
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
        if line in ("", PROP_NONE, "(null)"):
            return ""
        return line
    except (OSError, subprocess.TimeoutExpired):
        return ""


def apply_adb_bundle_track(adb: Path, mode: str, package: str = "") -> None:
    if not adb or not adb.is_file():
        raise FileNotFoundError(f"adb không tìm thấy: {adb}")
    mode = str(mode or MODE_ALL).strip().lower()
    if mode == MODE_SINGLE:
        value = str(package or "").strip()
        if not value:
            raise ValueError("Package name trống.")
    else:
        value = PROP_NONE
    subprocess.run(
        [str(adb), "shell", "setprop", "debug.firebase.analytics.app", value],
        check=True,
        timeout=15,
    )


def reassert_adb_single_track(adb: Path, cfg: dict) -> bool:
    """Giữ setprop đúng package khi mode single (app khác có thể làm lệch getprop)."""
    if not cfg or cfg.get("mode") != MODE_SINGLE:
        return False
    want = str(cfg.get("package") or "").strip()
    if not want or not adb or not adb.is_file():
        return False
    cur = read_adb_debug_app(adb)
    if cur == want:
        return False
    apply_adb_bundle_track(adb, MODE_SINGLE, want)
    return True
