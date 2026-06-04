#!/usr/bin/env python3
"""Xuất snapshot HTML viewer (parity với windows/capture_fa_logging.ps1)."""

from __future__ import annotations

import json
from pathlib import Path


def _escape_json_for_script(obj: dict) -> str:
    raw = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    return raw.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")


def write_fa_logging_html(
    *,
    output_path: Path,
    viewer_index: Path,
    viewer_rel: str,
    events: list[dict],
    properties: list[dict],
    property_latest: dict,
    filter_config: dict,
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)

    bootstrap = _escape_json_for_script(
        {
            "events": events,
            "properties": properties,
            "propertyLatest": property_latest,
        }
    )
    filter_json = _escape_json_for_script(filter_config)

    index_html = viewer_index.read_text(encoding="utf-8")
    index_html = index_html.replace('href="/app.css"', f'href="{viewer_rel}/app.css"')
    index_html = index_html.replace(
        'src="/value_type.js"', f'src="{viewer_rel}/value_type.js"'
    )
    index_html = index_html.replace('src="/app.js"', f'src="{viewer_rel}/app.js"')

    bootstrap_script = f"""  <script>
    window.__FA_FILE_MODE__ = true;
    window.__FA_BOOTSTRAP__ = {bootstrap};
    window.__FA_FILTER_CONFIG__ = {filter_json};
  </script>"""

    needle = f'<script src="{viewer_rel}/value_type.js"></script>'
    if needle not in index_html:
        raise ValueError(f"Không tìm thấy {needle} trong viewer template.")

    index_html = index_html.replace(
        needle, bootstrap_script + "\n  " + needle, 1
    )
    output_path.write_text(index_html, encoding="utf-8", newline="\n")
