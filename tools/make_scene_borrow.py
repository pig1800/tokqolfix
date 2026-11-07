#!/usr/bin/env python3
"""Build decomp/text/kanji_plan/scene_borrow.tsv from a survey capture.

The capture directory is written by tools/lua/scene_borrow_kanji.lua:
    index.txt: f=... bank=.. addr=.... code=...
    c_<frame>_<bank>_<addr>.bin: 8 KiB CHR RAM at the first glyph upload

A tile is borrowed when its 16 CHR bytes do not equal the bank-9 kana row
(8 bytes) followed by eight zero bytes.  Both 4 KiB CHR banks are checked and
the bank with more font matches is used.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ORIGINAL = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
CAPTURE = ROOT / "out" / "test" / "borrow_kanji"
MESSAGE_MAP = ROOT / "decomp" / "build" / "kanji" / "message_map.json"
OUT = ROOT / "decomp" / "text" / "kanji_plan" / "scene_borrow.tsv"


def font_rows() -> bytes:
    rom = ORIGINAL.read_bytes()
    return rom[16 + 9 * 0x4000 + 0x3A00:16 + 9 * 0x4000 + 0x3E00]


def main() -> int:
    font = font_rows()
    message_map = json.loads(MESSAGE_MAP.read_text(encoding="utf-8"))
    labels_by_addr: dict[tuple[int, int], list[str]] = {}
    for label, (bank, addr) in message_map.items():
        labels_by_addr.setdefault((bank, addr), []).append(label)

    rows: dict[str, set[int]] = {}
    for line in (CAPTURE / "index.txt").read_text(encoding="utf-8").splitlines():
        fields = dict(part.split("=") for part in line.split())
        frame = int(fields["f"])
        bank = int(fields["bank"], 16)
        addr = int(fields["addr"], 16)
        path = CAPTURE / f"c_{frame:05d}_{bank:02X}_{addr:04X}.bin"
        if not path.exists():
            continue
        data = path.read_bytes()
        best_base = 0
        best_match = -1
        for base in (0x0000, 0x1000):
            match = sum(1 for t in range(128)
                        if data[base + t * 16:base + (t + 1) * 16]
                        == font[t * 8:(t + 1) * 8] + b"\x00" * 8)
            if match > best_match:
                best_match = match
                best_base = base
        borrowed = {t for t in range(128)
                    if data[best_base + t * 16:best_base + (t + 1) * 16]
                    != font[t * 8:(t + 1) * 8] + b"\x00" * 8}
        for label in labels_by_addr.get((bank, addr), []):
            rows.setdefault(label, set()).update(borrowed)

    lines = ["# label\ttiles borrowed by the scene at message open "
             "(hex, comma separated; - = none)"]
    for label in sorted(rows):
        tiles = sorted(rows[label])
        spec = ",".join(f"{tile:02X}" for tile in tiles) if tiles else "-"
        lines.append(label + "\t" + spec)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {OUT} ({len(rows)} labels)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
