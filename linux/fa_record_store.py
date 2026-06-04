#!/usr/bin/env python3
"""Lưu events và user properties riêng, mỗi loại tối đa 10k bản ghi."""

from __future__ import annotations

MAX_FA_EVENTS = 10_000
MAX_FA_PROPERTIES = 10_000


def _bundle_key(bundle_id) -> str:
    return str(bundle_id or "")


class FaRecordStore:
    def __init__(self) -> None:
        self.events: list[dict] = []
        self.properties: list[dict] = []
        self.property_latest: dict[str, dict[str, dict]] = {}

    def add_event(self, record: dict) -> None:
        self.events.append(dict(record))
        while len(self.events) > MAX_FA_EVENTS:
            self.events.pop(0)

    def add_property(self, record: dict) -> None:
        rec = dict(record)
        name = rec.get("name")
        if not name:
            return
        self.properties.append(rec)
        while len(self.properties) > MAX_FA_PROPERTIES:
            self.properties.pop(0)
        bk = _bundle_key(rec.get("bundleId"))
        bucket = self.property_latest.setdefault(bk, {})
        bucket[name] = rec

    def add_record(self, record: dict) -> None:
        if record.get("type") == "event":
            self.add_event(record)
        elif record.get("type") == "user_property":
            self.add_property(record)

    def clear(self) -> None:
        self.events.clear()
        self.properties.clear()
        self.property_latest.clear()
