#!/usr/bin/env python3
"""Merge the QA screen-tile surveys into scene_borrow.tsv.

Inputs:
  out/qa/report.json        history/shop warp sweep (page-1 screen tiles)
  out/qa/field_report.json  field warp sweep (command menu visible)
  decomp/text/kanji_plan/scene_borrow.tsv  existing two-column table

Output columns:
  label <TAB> scene borrow <TAB> screen-referenced tiles

The compiler unions every column, so the scene borrow (oath range) and the
measured screen tiles are both reserved.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HISTORY = ROOT / "out" / "qa" / "report.json"
FIELD = ROOT / "out" / "qa" / "field_report.json"
OUT = ROOT / "decomp" / "text" / "kanji_plan" / "scene_borrow.tsv"


def load_old() -> dict[str, list[set[int]]]:
    rows: dict[str, list[set[int]]] = {}
    if not OUT.exists():
        return rows
    for line in OUT.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        label = parts[0]
        cols = []
        for spec in parts[1:]:
            spec = spec.strip()
            cols.append(set() if spec in ("", "-") else {
                int(t, 16) for t in spec.split(",")})
        rows[label] = cols
    return rows


def msg_label(index: int) -> str:
    if index < 0x200:
        return f"b10_msg_{index:03d}"
    return f"b11_msg_{index - 0x200:03d}"


def collect(report: Path, table: dict[str, set[int]]) -> None:
    if not report.exists():
        return
    data = json.loads(report.read_text(encoding="utf-8"))
    for row in data.get("results", []):
        screen = row.get("screen")
        if not screen:
            continue
        label = msg_label(row["index"])
        table.setdefault(label, set()).update(screen)


def collect_pages(report: Path, table: dict[str, set[int]]) -> None:
    """Use page-1 screen tiles from the per-page sweep when available."""
    if not report.exists():
        return
    data = json.loads(report.read_text(encoding="utf-8"))
    for row in data.get("results", []):
        for page in row.get("pages", []):
            if page.get("page") != 1:
                continue
            screen = page.get("screen")
            if screen:
                table.setdefault(msg_label(row["index"]), set()).update(screen)


def spec(tiles: set[int]) -> str:
    return ",".join(f"{t:02X}" for t in sorted(tiles)) if tiles else "-"


def main() -> int:
    old = load_old()
    screen: dict[str, set[int]] = {}
    collect(HISTORY, screen)
    collect(FIELD, screen)
    collect_pages(ROOT / "out" / "qa" / "pages_report.json", screen)
    labels = sorted(set(old) | set(screen))
    lines = ["# label\tscene borrow at message open\tscreen-referenced tiles "
             "(hex, comma separated; - = none)"]
    for label in labels:
        borrow = set()
        if label in old and old[label]:
            borrow = old[label][0]
        screen_tiles = screen.get(label, set())
        lines.append(f"{label}\t{spec(borrow)}\t{spec(screen_tiles)}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {OUT}: {len(labels)} labels, "
          f"{sum(1 for v in screen.values() if v)} surveyed screens")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
