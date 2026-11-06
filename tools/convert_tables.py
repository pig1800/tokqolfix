#!/usr/bin/env python3
"""Convert the word/place/item tables to a kanji planning text.

The message text inserts these strings through <WORD>, <PLACE>, and <ITEM>.
They are separate tables, so they are converted separately for the glyph
inventory.  Output is for planning only.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import textdata
from fix_kanji_plan import REPLACEMENTS
from make_kanji_plan import convert_string, _load

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "decomp" / "text" / "kanji_plan"


def apply_replacements(s: str) -> str:
    for old in sorted(REPLACEMENTS, key=len, reverse=True):
        s = s.replace(old, REPLACEMENTS[old])
    return s


def main() -> int:
    _load()
    tables = {
        "word": textdata.dictionary_entries(),
        "place": textdata.place_entries(),
        "item": textdata.item_entries(),
    }
    out = {}
    for name, entries in tables.items():
        rows = []
        context = ""
        for idx in sorted(entries):
            raw = entries[idx]
            if not raw:
                continue
            source = textdata._annotate(raw)
            if not source:
                continue
            converted, context = convert_string(source, context)
            converted = apply_replacements(converted)
            rows.append({"index": idx, "source": source, "kanji": converted})
        out[name] = rows
        lines = [f"# {name} table -- kanji planning version", ""]
        for row in rows:
            lines.append(f"{row['index']:02X}\t{row['source']}\t{row['kanji']}")
        (OUT_DIR / f"{name}_table_kanji.txt").write_text(
            "\n".join(lines) + "\n", encoding="utf-8"
        )
        print(f"{name}: {len(rows)} entries")
    (OUT_DIR / "tables_kanji.json").write_text(
        json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
