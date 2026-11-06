#!/usr/bin/env python3
"""Shared kanji inventory/encoding helpers for the SUROM kanji target."""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

import textdata

ROOT = Path(__file__).resolve().parent.parent
PLAN = ROOT / "decomp" / "text" / "kanji_plan"
FONT_TTF = ROOT / "DotGothic16-Regular.ttf"
INDEX_TSV = ROOT / "assets" / "fonts" / "kanji_index.tsv"

KANJI_RE = re.compile(r"[\u3400-\u9fff\uf900-\ufaff]")

# The dialogue sources that define the hack's inventory.  Both are the
# corrected machine drafts; they are the editable source for the kanji target.
DTX_FILES = (
    PLAN / "bank10_messages_kanji_fixed.dtx",
    PLAN / "bank11_messages_kanji_fixed.dtx",
)


def _count_literal(text: str, counts: Counter[str]) -> None:
    """Count kanji outside <...> tokens."""
    out = []
    i = 0
    while i < len(text):
        if text[i] == "<":
            j = text.find(">", i + 1)
            if j < 0:
                break
            i = j + 1
            continue
        out.append(text[i])
        i += 1
    for ch in KANJI_RE.findall("".join(out)):
        counts[ch] += 1


def inventory() -> list[tuple[str, int]]:
    """Return (character, count) in stable code order.

    Codes 0-255 are the most frequent so most text uses the shortest escape
    ($EC nn).  Ties are broken by first appearance.
    """
    counts: Counter[str] = Counter()
    first: dict[str, int] = {}
    order = 0
    for path in DTX_FILES:
        text = path.read_text(encoding="utf-8")
        _count_literal(text, counts)
        for m in re.finditer(r"<(WORD|PLACE|ITEM):([0-9A-Fa-f]{2})", text):
            typ, idx = m.group(1), int(m.group(2), 16)
            table = {
                "WORD": textdata.dictionary_entries,
                "PLACE": textdata.place_entries,
                "ITEM": textdata.item_entries,
            }[typ]()
            data = table.get(idx, b"")
            try:
                s = textdata.encode_record(data)
            except Exception:
                continue
            _count_literal(s, counts)
        for m in KANJI_RE.finditer(text):
            first.setdefault(m.group(0), order)
            order += 1
    # Stable order: frequency desc, first appearance asc.
    chars = sorted(counts, key=lambda ch: (-counts[ch], first.get(ch, 10**9), ord(ch)))
    return [(ch, counts[ch]) for ch in chars]


def code_map() -> dict[str, int]:
    return {ch: i for i, (ch, _) in enumerate(inventory())}


def glyph_bytes(ch: str, font_size: int = 16, threshold: int = 128) -> bytes:
    """Render one kanji to 32-byte 1bpp: 16 rows x 2 bytes (left, right)."""
    from PIL import Image, ImageDraw, ImageFont

    font = ImageFont.truetype(str(FONT_TTF), font_size)
    img = Image.new("L", (16, 16), 0)
    draw = ImageDraw.Draw(img)
    draw.text((0, 0), ch, font=font, fill=255, anchor="lt")
    out = bytearray()
    for y in range(16):
        left = 0
        right = 0
        for x in range(8):
            if img.getpixel((x, y)) >= threshold:
                left |= 0x80 >> x
            if img.getpixel((x + 8, y)) >= threshold:
                right |= 0x80 >> x
        out += bytes((left, right))
    return bytes(out)


def write_index() -> list[tuple[str, int]]:
    inv = inventory()
    INDEX_TSV.parent.mkdir(parents=True, exist_ok=True)
    lines = ["# code\tchar\tcount"]
    for i, (ch, n) in enumerate(inv):
        lines.append(f"{i:04X}\t{ch}\t{n}")
    INDEX_TSV.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return inv
