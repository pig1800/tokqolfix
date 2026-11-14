#!/usr/bin/env python3
"""Build the 16x16 kanji font for the expanded target from Izumi16's
embedded 16-pixel bitmaps (kanji_common.glyph_bytes; never its outlines).
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

from kanji_common import (FALLBACK_USED, INDEX_TSV, MAX_GLYPHS,
                          code_of, glyph_bytes, write_index)

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "decomp" / "build" / "kanji"
SHEET = OUT / "kanji_16x16_ext.png"          # contact sheet (build output)


def build() -> int:
    inv = write_index()
    if len(inv) > MAX_GLYPHS:
        raise SystemExit(f"inventory too large: {len(inv)} > {MAX_GLYPHS}")
    OUT.mkdir(parents=True, exist_ok=True)
    data = bytearray()
    for i, (ch, _) in enumerate(inv):
        g = glyph_bytes(ch)
        assert len(g) == 32
        data += g
    (OUT / "kanji_font.bin").write_bytes(bytes(data))
    # 16 glyphs per row, 32 rows (one extra row for spacer)
    cols = 16
    rows = (len(inv) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 17, rows * 17), (24, 24, 24))
    draw = ImageDraw.Draw(sheet)
    for i, (ch, _) in enumerate(inv):
        g = data[i * 32:(i + 1) * 32]
        x0 = (i % cols) * 17
        y0 = (i // cols) * 17
        for y in range(16):
            lo, hi = g[y * 2], g[y * 2 + 1]
            for x in range(8):
                if lo & (0x80 >> x):
                    sheet.putpixel((x0 + x, y0 + y), (240, 240, 220))
                if hi & (0x80 >> x):
                    sheet.putpixel((x0 + 8 + x, y0 + y), (240, 240, 220))
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(SHEET)
    print(f"kanji inventory: {len(inv)} glyphs -> {OUT / 'kanji_font.bin'}")
    fb = ["# glyphs Izumi16 has no 16-pixel bitmap for (kanji_common.glyph_bytes)",
          "# code\tchar\tU+\tfont\tcount"]
    counts = dict(inv)
    order = {ch: i for i, (ch, _) in enumerate(inv)}
    for ch, name in sorted(FALLBACK_USED.items(), key=lambda kv: order.get(kv[0], 0)):
        print(f"  no Izumi16 bitmap for U+{ord(ch):04X}: {name}")
        fb.append("\t".join((f"{code_of(order[ch]):04X}", ch, f"U+{ord(ch):04X}", name, str(counts.get(ch, 0)))))
    (OUT / "kanji_fallback.tsv").write_text(chr(10).join(fb) + chr(10), encoding="utf-8")
    if any(name == "none" for name in FALLBACK_USED.values()):
        raise SystemExit("a kanji has no Izumi16 bitmap or composite")
    print(f"contact sheet:   {SHEET}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["build"], nargs="?", default="build")
    ap.parse_args()
    return build()


if __name__ == "__main__":
    raise SystemExit(main())
