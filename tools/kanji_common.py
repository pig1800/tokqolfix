#!/usr/bin/env python3
"""Shared kanji inventory/encoding helpers for the SUROM kanji target."""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

import textdata

ROOT = Path(__file__).resolve().parent.parent
PLAN = ROOT / "decomp" / "text" / "kanji_plan"
FONT_TTF = ROOT / "JF-Dot-Shinonome16.ttf"
INDEX_TSV = ROOT / "assets" / "fonts" / "kanji_index.tsv"

# U+3005 (iteration mark) is a 16x16 glyph too (revision 15).
KANJI_RE = re.compile(r"[\u3005\u3400-\u9fff\uf900-\ufaff]")

# The dialogue sources that define the hack's inventory.  Both are the
# corrected machine drafts; they are the editable source for the kanji target.
# Revision 14: the Opus re-conversion laid out by tools/kanji_layout.py
# (bank1X_messages_kanji_r14.dtx) replaces the machine drafts when present.
_R14 = (PLAN / "bank10_messages_kanji_r14.dtx", PLAN / "bank11_messages_kanji_r14.dtx")
DTX_FILES = _R14 if all(p.exists() for p in _R14) else (
    PLAN / "bank10_messages_kanji_fixed.dtx",
    PLAN / "bank11_messages_kanji_fixed.dtx",
)


# Print helpers ($F8 CALL) that show one of two fixed officer names: bank 13
# $A1D0/$A1D4 print officer $0A (ソウジン) or $0B (ソウユウ) from the runtime
# name table, the talked-to brother first.  The kanji target compiles them
# as a kanji pick on the same test: ptr -> (officer id, name shown when the
# talked-to actor is that officer, name shown otherwise).
KANJI_CALLS = {
    0x21D0: (0x0A, "宋仁", "宋勇"),
    0x21D4: (0x0B, "宋仁", "宋勇"),
}

# Print helpers that add fixed kana tiles after a name.  $D549 (battle
# result, b10_msg_055) draws the target's name ($D49A) and then the tiles
# のへい when the target unit ($60A8,[$4B]) is 8 or up.  The kanji target
# compiles it as <CALL:name helper> plus a troop pick on the same test:
# ptr -> (name helper, text shown when the test passes, text otherwise).
KANJI_TROOP_CALLS = {
    0xD549: (0xD49A, "の兵", ""),
}

# Print helpers whose fixed kana tail has a kanji form of the same width.
# $D565 (strategy name: three messages) draws the name and then のけい
# unconditionally; the kanji target follows the call with $EE $FC n (the
# buffer position goes back n cells, over けい) and the kanji: ptr ->
# (cells, text).
KANJI_SUFFIX_CALLS = {
    0xD565: (2, "計"),
}


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
        for m in re.finditer(r"<CALL:([0-9A-Fa-f]{4})", text):
            ptr = int(m.group(1), 16)
            pick = KANJI_CALLS.get(ptr) or KANJI_TROOP_CALLS.get(ptr)
            if ptr in KANJI_SUFFIX_CALLS:
                pick = (None, KANJI_SUFFIX_CALLS[ptr][1], "")
            if pick:
                for ch in KANJI_RE.findall(pick[1] + pick[2]):
                    counts[ch] += 1
                    first.setdefault(ch, order)
                    order += 1
        for m in KANJI_RE.finditer(text):
            first.setdefault(m.group(0), order)
            order += 1
    # Stable order: frequency desc, first appearance asc.
    chars = sorted(counts, key=lambda ch: (-counts[ch], first.get(ch, 10**9), ord(ch)))
    return [(ch, counts[ch]) for ch in chars]


GLYPHS_PER_BANK = 359          # glyphs per hack bank (32 tables x 359)
GLYPH_BANKS_MAX = 8            # banks 23-30
MAX_GLYPHS = GLYPHS_PER_BANK * GLYPH_BANKS_MAX


def code_of(index: int) -> int:
    """Text code of inventory entry `index`: bank n holds codes n*512 + 0..358,
    so the NMI reads the bank from the code's high byte directly.  Codes
    0-511 use the 2-byte escape $EC/$ED lo, the rest $EE hi lo."""
    return (index // GLYPHS_PER_BANK) * 512 + index % GLYPHS_PER_BANK


def code_map() -> dict[str, int]:
    return {ch: code_of(i) for i, (ch, _) in enumerate(inventory())}


# Glyphs missing from the primary font are drawn from these, in order, and
# reported by the font builder.  (JF-Dot-Shinonome16 lacks a few JIS X 0212
# characters such as 鄧 and 瓚.)
FALLBACK_FONTS = (
    ROOT / "DotGothic16-Regular.ttf",
    Path("C:/Windows/Fonts/msgothic.ttc"),
)
FALLBACK_USED: dict[str, str] = {}
DOTGOTHIC_DY = 1               # rows to move DotGothic16 glyphs down


def _covers(path: Path, ch: str) -> bool:
    from fontTools.ttLib import TTFont, TTCollection
    try:
        if path.suffix.lower() == ".ttc":
            fonts = TTCollection(str(path)).fonts
        else:
            fonts = [TTFont(str(path))]
    except Exception:
        return False
    return any(ord(ch) in f.getBestCmap() for f in fonts)


def font_for(ch: str) -> Path:
    if _covers(FONT_TTF, ch):
        return FONT_TTF
    for path in FALLBACK_FONTS:
        if path.exists() and _covers(path, ch):
            FALLBACK_USED[ch] = path.name
            return path
    FALLBACK_USED[ch] = "none"
    return FONT_TTF


def glyph_bytes(ch: str, font_size: int = 16, threshold: int = 128) -> bytes:
    """Render one kanji to 32-byte 1bpp: 16 rows x 2 bytes (left, right)."""
    from PIL import Image, ImageDraw, ImageFont

    path = font_for(ch)
    font = ImageFont.truetype(str(path), font_size)
    img = Image.new("L", (16, 16), 0)
    draw = ImageDraw.Draw(img)
    # DotGothic16 sits one pixel higher than Shinonome on the 16x16 grid.
    dy = DOTGOTHIC_DY if path.name.lower().startswith("dotgothic") else 0
    draw.text((0, dy), ch, font=font, fill=255, anchor="lt")
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
