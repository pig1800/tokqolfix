#!/usr/bin/env python3
"""Compile the proofread kanji draft into the expanded text banks.

Each unique message is packed into a text bank (18-22) together with its
page records.  Bank 10/11 keep the original pointer tables and hold an
8-byte trampoline per message:

    F8 3A C6 <text bank> <text addr lo/hi> <meta addr lo/hi>

The F8 trampoline maps the text bank and enters the ROM-resident overlay at
$B800.  Page records are static:

    count byte, count * (code_lo, code_hi, tile0, tile1, tile2, tile3)

The compiler assigns the four CHR tiles for every kanji from the free kana
tiles of that page.  Runtime state is a dirty-CHR bitmap in internal RAM;
there is no CHR scan, no allocation and no battery-RAM use.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

from kanji_common import KANJI_CALLS, KANJI_SUFFIX_CALLS, KANJI_TROOP_CALLS, code_map, inventory
import textdata

ROOT = Path(__file__).resolve().parent.parent
PLAN = ROOT / "decomp" / "text" / "kanji_plan"
OUT = ROOT / "decomp" / "build" / "kanji"
INDEX_SYMBOLS = ROOT / "decomp" / "build" / "text" / "index_symbols.inc"

BANK_INFO = {
    10: {"count": 488, "lo": 0x0000, "hi": 0x0200, "data": 0x03E8, "tail": 0x3DD3},
    11: {"count": 384, "lo": 0x0000, "hi": 0x0200, "data": 0x0380, "tail": 0x33F0},
}
DATA_START = {10: 0x03E8, 11: 0x0380}
TRAMPOLINE_ADDR = 0xBF00     # F8 body, identical in banks 10/11
MAX_PAGES = 32
META_WIN = 0x20             # kanji.inc: metadata byte 0 bit 5, a victory message
# b10_msg_059 「…との戦いに勝った」 (after the scripted battles' victory face),
# 061 / 062 (the rewards): the battle is won (kanji_overlay message_setup).
WIN_LABELS = {"b10_msg_059", "b10_msg_061", "b10_msg_062"}
MAX_PAGE_ENTRIES = 16
# Free tiles a page must leave unassigned.  Revision 16: 0 (was 4, a slack
# from the shared-CHR design; the runtime never needs a spare tile).
PAGE_TILE_MARGIN = 0
TEXT_BANKS = [18, 19, 20, 21, 22]          # grown into 30, 29, ... as needed
TEXT_BANKS_EXTRA = [30, 29, 26, 25]   # never the glyph banks (23 + n), 27 (the canvas RAM image, kanji_build.CV_BANK) or 28 (the UI bank, kanji_build.UI_BANK)
TEXT_BANK_LIMIT = 0x3800     # overlay occupies $B800-$BFFF
OVERLAY_SIZE = 0x800
SCENE_BORROW = set(range(0x42, 0x5C))  # measured oath-scene overwrite range
SCENE_BORROW_FILE = PLAN / "scene_borrow.tsv"


def far_stub_addr() -> int:
    path = OUT / "far_stub.txt"
    if not path.exists():
        raise SystemExit("missing far_stub.txt; assemble the fixed hooks first")
    return int(path.read_text(encoding="utf-8").strip(), 16)


def load_scene_borrow() -> dict[str, set[int]]:
    table: dict[str, set[int]] = {}
    if not SCENE_BORROW_FILE.exists():
        return table
    for line in SCENE_BORROW_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        label = parts[0]
        tiles: set[int] = set()
        for spec in parts[1:]:
            spec = spec.strip()
            if spec and spec != "-":
                tiles |= {int(tile, 16) for tile in spec.split(",")}
        table[label] = tiles
    return table


SCENE_BORROW_BY_LABEL = load_scene_borrow()


# Lower kana tiles drawn by the original name-entry screen (extracted from
# PPU $2000/$2400 at the name-entry frame).  The two history prompts run on
# that screen, so their kanji must not borrow any of these tiles.
SAVENAME_TILES = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A,
    0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A,
    0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x29, 0x2A,
    0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35,
    0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40,
    0x41, 0x5D, 0x5E, 0x5F, 0x60, 0x61, 0x70, 0x72, 0x73, 0x79,
}

# Prompt list tags.  The default heuristic tags any question-ending message
# as "menu"; the history prompts use the name-entry charset (hiragana and
# symbols), which leaves the katakana block free for their kanji.
LIST_TAG_OVERRIDES = {
    "b11_msg_146": "savename",
    "b11_msg_147": "savename",
    "b11_msg_148": "savename",
    "b11_msg_149": "savename",
    "b11_msg_150": "savename",
    "b11_msg_151": "savename",
    "b11_msg_152": "savename",
}

# Tiles that must survive while a message page owns the CHR cache.
#   digits 0-9, blank, cursor arrow, dakuten/handakuten marks, frame pieces
FRAME_TILES = set(textdata.FRAME_BYTE_TO_TOKEN)
# $70 is the menu cursor (a background tile in every menu window).
CURSOR_TILES = {0x0A, 0x70, 0x71, 0x72, 0x73}
DIGIT_TILES = set(range(0x0A))

# Inline bank-15 menu scripts ($E948-$EDA0; text_init's menu table is at
# $EDA1/$EDD1).  The game draws a menu window beside or below the text window
# and keeps it there while it prints further messages, so menu kana share the
# band page with those messages' kanji (revision 16: the partner shop's
# のうりょく/くわえる/はずす/かいこ under 「...様、ご用件を...」).  The
# name-entry kana grid (menu $26) is drawn only on the history name-entry
# screen; its prompts reserve SAVENAME_TILES instead.
MENU_REGIONS = ((0x2948, 0x2C66), (0x2C66, 0x2D43), (0x2D43, 0x2DA1))
NAME_GRID_REGION = (0x2C66, 0x2D43)
# Menus that bank-13 event code opens next to a message: はい/いいえ (menus
# $02 and $25) and きろく/よぶ ($24).  Its other menus are the name entry
# ($26) and windows without kana.
EVENT_MENU_REGIONS = ((0x2974, 0x297F), (0x2C50, 0x2C66))


def menu_stream_tiles(regions=MENU_REGIONS) -> set[int]:
    b = textdata.bank_bytes(15)
    used: set[int] = set()
    for start, end in regions:
        data = b[start:end]
        i = 0
        while i < len(data):
            x = data[i]
            if x in (0xEF, 0xF0, 0xF1, 0xF2) and i + 1 < len(data):
                i += 2
                continue
            if x in (0xF8, 0xF9) and i + 2 < len(data):
                i += 3
                continue
            if 0xF3 <= x <= 0xF7 or x >= 0xFA:
                i += 1
                continue
            if x >= 0x80:
                used.add(0x72)
                base = x & 0x7F
                used.add((base - 0x0A) & 0xFF if base >= 0x62 else base)
            else:
                used.add(x)
            i += 1
    return used


MENU_TILES = menu_stream_tiles()
NAME_GRID_TILES = menu_stream_tiles((NAME_GRID_REGION,))
SUBMENU_TILES = menu_stream_tiles(tuple(r for r in MENU_REGIONS if r != NAME_GRID_REGION))
EVENT_MENU_TILES = menu_stream_tiles(EVENT_MENU_REGIONS)
# $6C (金) and $7F (兵) are used as field-map icons; never borrow them.
RESERVED_TILES = FRAME_TILES | CURSOR_TILES | DIGIT_TILES | {0x6C, 0x7F}

# Unsurveyed messages can be opened on a field screen where the command menu
# is visible.  Measured from the town field capture at message open
# (out/test/fk/fk_4400_ppu.bin): every lower tile referenced by either
# nametable, including the command-menu kana and field HUD.  Add the measured
# 26-tile oath-scene borrow until a per-message survey narrows it.
FIELD_SCENE_TILES = {
    0x00, 0x03, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12,
    0x13, 0x15, 0x16, 0x17, 0x1A, 0x1C, 0x1E, 0x1F, 0x24, 0x2F, 0x30,
    0x31, 0x33, 0x34, 0x3B, 0x3E, 0x3F, 0x41, 0x4A, 0x4B, 0x55, 0x5A,
    0x5D, 0x5F, 0x60, 0x66, 0x68, 0x6B, 0x6D, 0x6E, 0x6F, 0x70, 0x72,
    0x76, 0x77, 0x7D, 0x7E,
}
SCENE_FALLBACK = set(FIELD_SCENE_TILES) | set(SCENE_BORROW)


def tiles_for_string(s: str) -> set[int]:
    used: set[int] = set()
    for ch in re.sub(r"<[^>]*>", "", s):
        b = char_to_byte(ch)
        if b is not None:
            kana_tiles_for_byte(b, used)
    return used


def name_table_entry(idx: int) -> bytes:
    b12 = textdata.bank_bytes(12)
    p = b12[0x2800 + idx] | (b12[0x2900 + idx] << 8)
    if not (0x8000 <= p < 0xC000):
        return b""
    off = p - 0x8000 + 0x14
    end = b12.find(b"\xff", off)
    return b"" if end < 0 else b12[off:end]


_NAME_TILE_CACHE: dict[int, set[int]] = {}


def name_tiles_for_index(idx: int) -> set[int]:
    if idx not in _NAME_TILE_CACHE:
        try:
            s = textdata.encode_record(name_table_entry(idx))
        except Exception:
            s = ""
        _NAME_TILE_CACHE[idx] = tiles_for_string(s)
    return _NAME_TILE_CACHE[idx]


def item_name_tiles() -> set[int]:
    global _ITEM_NAME_TILES
    try:
        return _ITEM_NAME_TILES
    except NameError:
        pass
    used: set[int] = set()
    for data in textdata.item_entries().values():
        try:
            used |= tiles_for_string(textdata.encode_record(data))
        except Exception:
            continue
    _ITEM_NAME_TILES = used
    return used


def party_name_tiles() -> set[int]:
    global _PARTY_NAME_TILES
    try:
        return _PARTY_NAME_TILES
    except NameError:
        pass
    used: set[int] = set()
    for i in range(256):
        used |= name_tiles_for_index(i)
    _PARTY_NAME_TILES = used
    return used


# U+3005 (iteration mark) is a 16x16 glyph too (revision 15).
KANJI_RE = re.compile(r"[\u3005\u3400-\u9fff\uf900-\ufaff]")
LINE_CTRL = {"<NL>", "<NL2>", "<WAIT>", "<PAGE>", "<END>", "<END_NOWAIT>"}


def char_to_byte(ch: str) -> int | None:
    """Map a visible character to a font byte, normalising missing kana.

    The original 8x8 font has no katakana ヘ/ベ; the model draft occasionally
    uses them.  Falling back to the hiragana form keeps the text readable and
    stays inside the original font.
    """
    b = textdata.CHAR_TO_BYTE.get(ch)
    if b is not None:
        return b
    o = ord(ch)
    if 0x30A1 <= o <= 0x30F6:
        return textdata.CHAR_TO_BYTE.get(chr(o - 0x60))
    return None


@dataclass
class Record:
    labels: list[str]
    text: str
    data: bytes = b""
    pages: list[list["Page"]] = field(default_factory=list)
    data_bank: int = 0
    data_addr: int = 0
    relaxed: bool = False


@dataclass
class Page:
    tokens: list[str]
    entries: list[tuple[int, int, int]] = field(default_factory=list)  # code, base
    used: set[int] = field(default_factory=set)
    kanji_order: list[int] = field(default_factory=list)
    last_line_codes: list[int] = field(default_factory=list)
    line_codes: list[list[int]] = field(default_factory=list)
    line_used: list[set[int]] = field(default_factory=list)
    line_codes_all: list[list[int]] = field(default_factory=list)
    names: int = 0          # runtime officer names ($F4-$F7) on the page


def parse_dtx(path: Path) -> list[Record]:
    records: list[Record] = []
    pending: list[str] = []
    strings: list[str] = []

    def flush() -> None:
        nonlocal pending, strings
        if not pending:
            return
        records.append(Record(pending, "".join(strings)))
        pending = []
        strings = []

    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):$", line)
        if m:
            if strings:
                flush()
            pending.append(m.group(1))
            continue
        m = re.match(r'^"(.*)"$', line)
        if m:
            if not pending:
                raise ValueError(f"{path}:{lineno}: string without a label")
            strings.append(m.group(1))
            continue
        raise ValueError(f"{path}:{lineno}: expected label or quoted string")
    flush()
    return records


def tokenize(text: str) -> list[str]:
    out: list[str] = []
    i = 0
    while i < len(text):
        if text[i] == "<":
            j = text.find(">", i + 1)
            if j < 0:
                raise ValueError(f"unterminated token: {text[i:i+40]!r}")
            out.append(text[i:j + 1])
            i = j + 1
        else:
            out.append(text[i])
            i += 1
    return out


# Battle-reward numbers (bank 14: $99DC experience, $9A3C gold, $9A65
# food): a 24-bit sum printed by $D6F3 without leading zeros.  Counted as
# 6 digits; the original's third line (「兵ろう　XXを　てにいれた」) left
# room for 7, the kanji one (「兵糧XXを手に入れた」) one cell less.
NUMBER_CALLS = {0x99DC: 6, 0x9A3C: 6, 0x9A65: 6}


def token_width(tok: str) -> int | None:
    """Visible width of one token, or None for a line-ending control."""
    if tok in LINE_CTRL:
        return None
    if not tok.startswith("<"):
        return 2 if KANJI_RE.match(tok) else 1
    key = tok[1:-1].split("=", 1)[0]
    if key.startswith(("WORD:", "PLACE:", "ITEM:")):
        typ, num = key.split(":", 1)
        table = {
            "WORD": textdata.dictionary_entries,
            "PLACE": textdata.place_entries,
            "ITEM": textdata.item_entries,
        }[typ]()
        try:
            data = table.get(int(num, 16), b"")
        except ValueError:
            return 1
        s = textdata.encode_record(data)
        return sum(2 if KANJI_RE.match(c) else 1 for c in re.sub(r"<[^>]*>", "", s))
    if key.startswith("CALL:") and int(key[5:9], 16) in NUMBER_CALLS:
        return NUMBER_CALLS[int(key[5:9], 16)]
    if key.startswith("NAME") or key.startswith("CALL:"):
        # Runtime names are 2-4 kana; CALL helpers print short names/numbers.
        return 8
    if key.startswith("JUMP:"):
        return 0
    return 1


def reflow(tokens: list[str]) -> list[str]:
    """Insert <NL2> before visible text would exceed 18 cells."""
    out: list[str] = []
    width = 0
    line_has = False
    for tok in tokens:
        w = token_width(tok)
        if w is None:
            out.append(tok)
            width = 0
            line_has = False
            continue
        if w and line_has and width + w > 18:
            out.append("<NL2>")
            width = 0
            line_has = False
        out.append(tok)
        if w:
            width += w
            line_has = True
    return out


def split_pages(tokens: list[str]) -> list[list[str]]:
    pages: list[list[str]] = [[]]
    for tok in tokens:
        if tok == "<PAGE>":
            pages.append([])
        else:
            pages[-1].append(tok)
    return pages


def page_padding(tokens: list[str], i: int) -> bytes:
    """Fresh-window pages: after the wait at tokens[i] (<PAGE>), two empty
    lines scroll the previous page out before the next page prints, so a
    page never shares the window (or CHR tiles) with the one before it.
    The line breaks match the page's own (<NL> keeps the dialogue indent)."""
    rest = tokens[i + 1:]
    visible = [t for t in rest if t not in LINE_CTRL and not t.startswith("<JUMP:")]
    if not FRESH_PAGES or not visible:
        return b""
    nl = None
    for t in rest:
        if t in ("<NL>", "<NL2>"):
            nl = t
            break
        if t in ("<PAGE>", "<WAIT>"):
            break
    if nl is None:
        nl = "<NL>" if tokens and tokens[0] == "「" else "<NL2>"
    code = textdata.CONTROL_TOKENS[nl]
    return bytes((code, code))


def compile_tokens(tokens: list[str], cmap: dict[str, int]) -> bytes:
    out = bytearray()
    i = 0
    while i < len(tokens):
        tok = tokens[i]

        if tok.startswith("<"):
            key = tok[1:-1].split("=", 1)[0].strip()
            if key.startswith("WORD:"):
                out += bytes((0xF0, int(key[5:], 16)))
            elif key.startswith("PLACE:"):
                out += bytes((0xEF, int(key[6:], 16)))
            elif key.startswith("ITEM:"):
                out += bytes((0xF1, int(key[5:], 16)))
            elif key.startswith("NAME:"):
                out += bytes((0xF2, int(key[5:], 16)))
            elif key.startswith("CALL:") and int(key[5:], 16) in KANJI_CALLS:
                # Kanji pick: $EE $FF id lenA, variant A, $EE $FE lenB,
                # variant B (kanji_overlay.asm kanji_ctl).
                oid, name_a, name_b = KANJI_CALLS[int(key[5:], 16)]
                vb = compile_tokens(list(name_b), cmap)
                va = compile_tokens(list(name_a), cmap) + bytes((0xEE, 0xFE, len(vb)))
                out += bytes((0xEE, 0xFF, oid, len(va))) + va + vb
            elif key.startswith("CALL:") and int(key[5:], 16) in KANJI_TROOP_CALLS:
                # Troop pick: <CALL:name helper>, $EE $FD lenA, variant A,
                # $EE $FE lenB, variant B (kanji_overlay.asm kanji_ctl).
                helper, text_a, text_b = KANJI_TROOP_CALLS[int(key[5:], 16)]
                vb = compile_tokens(list(text_b), cmap)
                va = compile_tokens(list(text_a), cmap) + bytes((0xEE, 0xFE, len(vb)))
                # The name helper $D49A is put_officer_name_target, which
                # the control $F4 runs too: $F4 goes through the overlay,
                # which puts the name in kanji in the battle's pool.
                call = bytes((0xF4,)) if helper == 0xD49A else bytes((0xF8, helper & 0xFF, helper >> 8))
                out += call + bytes((0xEE, 0xFD, len(va))) + va + vb
            elif key.startswith("CALL:") and int(key[5:], 16) in KANJI_SUFFIX_CALLS:
                # Kanji tail: the call, $EE $FC cells (back over the kana
                # tail), the kanji (kanji_overlay.asm kanji_ctl).
                ptr = int(key[5:], 16)
                cells, text = KANJI_SUFFIX_CALLS[ptr]
                tail = bytes((0xF8, ptr & 0xFF, ptr >> 8, 0xEE, 0xFC, cells))
                tail += compile_tokens(list(text), cmap)
                if ptr == 0xD565:
                    # The tactic's name: $EE $FB lenA, variant A (の計, after
                    # the name's kanji from the pool), $EE $FE lenB, variant
                    # B (the call and its kanji tail; kanji_overlay.asm
                    # kanji_ctl).  The name takes a page's reserved entries.
                    va = compile_tokens(list("の" + text), cmap) + bytes((0xEE, 0xFE, len(tail)))
                    out += bytes((0xEE, 0xFB, len(va))) + va + tail
                else:
                    out += tail
            elif key.startswith("CALL:"):
                ptr = int(key[5:], 16)
                out += bytes((0xF8, ptr & 0xFF, (ptr >> 8) & 0xFF))
            elif key.startswith("JUMP:"):
                ptr = int(key[5:], 16)
                out += bytes((0xF9, ptr & 0xFF, (ptr >> 8) & 0xFF))
            elif f"<{key}>" in textdata.CONTROL_TOKENS:
                out.append(textdata.CONTROL_TOKENS[f"<{key}>"])
            elif f"<{key}>" in textdata.FRAME_TOKEN_TO_BYTE:
                out.append(textdata.FRAME_TOKEN_TO_BYTE[f"<{key}>"])
            elif ":" in key:
                out.append(int(key.split(":", 1)[0], 16))
            else:
                out.append(int(key, 16))
            i += 1
            continue
        ch = tok
        if ch in cmap:
            code = cmap[ch]
            if code < 0x200:
                out += bytes((0xEC + (code >> 8), code & 0xFF))
            else:
                out += bytes((0xEE, code >> 8, code & 0xFF))
        else:
            b = char_to_byte(ch)
            if b is not None:
                out.append(b)
            elif ch == " ":
                out.append(0x0A)
            elif "0" <= ch <= "9":
                out.append(ord(ch) - ord("0"))
            else:
                raise ValueError(f"character {ch!r} U+{ord(ch):04X} has no tile/kanji code")
        i += 1
    return bytes(out)


def kana_tiles_for_byte(b: int, used: set[int]) -> None:
    if b >= 0x80:
        used.add(0x72)
        base = b & 0x7F
        used.add((base - 0x0A) & 0xFF if base >= 0x62 else base)
    elif b < 0xEF:
        used.add(b)


def call_tiles(ptr: int) -> set[int]:
    used: set[int] = set()
    s = textdata.CALL_ANNOTATIONS.get(ptr, "")
    for ch in s:
        b = char_to_byte(ch)
        if b is not None:
            kana_tiles_for_byte(b, used)
    return used


def page_from_bytes(data: bytes, extra_used: set[int] | None = None) -> tuple[list[Page], bool]:
    """Split one compiled message into pages and collect tile demand.

    Only tiles that can be on screen at the same time as a kanji are reserved:
    frame/cursor/digits plus the exact kana strings of table insertions.  The
    dynamic runtime name insertions use a bounded union (party-name table and
    item-name table).  Messages that leave a menu over the window reserve the
    menu kana stream as well.
    """
    base_used = set(RESERVED_TILES) | set(extra_used or ())
    pages: list[Page] = []
    page = Page([])
    used: set[int] = set(base_used)
    kanji: list[int] = []
    lines: list[list[int]] = [[]]
    line_used: list[set[int]] = [set()]
    i = 0

    def add_tiles(tiles: set[int]) -> None:
        used.update(tiles)
        line_used[-1].update(tiles)

    def finish() -> None:
        nonlocal page, used, kanji, lines, line_used
        page.used = set(used)
        page.kanji_order = list(kanji)
        page.line_codes = [list(line) for line in lines if line]
        page.line_used = [set(tiles) for tiles in line_used]
        page.line_codes_all = [list(line) for line in lines]
        page.last_line_codes = list(lines[-1]) if lines else []
        pages.append(page)
        page = Page([])
        used = set(base_used)
        kanji = []
        lines = [[]]
        line_used = [set()]

    while i < len(data):
        b = data[i]
        if b == 0xEE and i + 1 < len(data) and data[i + 1] >= 0xFB:
            # Kanji-pick control: both variants' kanji stay in the page.
            # $FB, the tactic's name, takes reserved entries like a name.
            if data[i + 1] == 0xFB:
                page.names += 1
            i += 4 if data[i + 1] == 0xFF else 3
            continue
        if 0xEC <= b <= 0xEE:
            n = 3 if b == 0xEE else 2
            if i + n - 1 >= len(data):
                break
            code = (data[i + 1] << 8 | data[i + 2]) if b == 0xEE else ((b - 0xEC) << 8) | data[i + 1]
            if code not in kanji:
                kanji.append(code)
            lines[-1].append(code)
            i += n
            continue
        if b in (0xEF, 0xF0, 0xF1, 0xF2) and i + 1 < len(data):
            idx = data[i + 1]
            table = {
                0xEF: textdata.place_entries,
                0xF0: textdata.dictionary_entries,
                0xF1: textdata.item_entries,
            }.get(b)
            if table is not None:
                try:
                    add_tiles(tiles_for_string(
                        textdata.encode_record(table().get(idx, b""))))
                except Exception:
                    pass
            elif b == 0xF2:
                add_tiles(name_tiles_for_index(idx))
            i += 2
            continue
        if b == 0xF3:
            add_tiles(item_name_tiles())
            i += 1
            continue
        if 0xF4 <= b <= 0xF7:
            add_tiles(party_name_tiles())
            page.names += 1
            i += 1
            continue
        if b in (0xF8, 0xF9) and i + 2 < len(data):
            if b == 0xF8:
                add_tiles(call_tiles(data[i + 1] | (data[i + 2] << 8)))
            else:
                # The original engine renders $F9 and both operand bytes as
                # cells; reserve the two operand tiles when they are glyphs.
                for x in (data[i + 1], data[i + 2]):
                    if x < 0xEC:
                        tmp: set[int] = set()
                        kana_tiles_for_byte(x, tmp)
                        add_tiles(tmp)
            i += 3
            continue
        if b == 0xFC:
            finish()
            i += 1
            continue
        if b in (0xFA, 0xFB):
            lines.append([])
            line_used.append(set())
            i += 1
            continue
        if b >= 0xFA:
            i += 1
            continue
        tmp: set[int] = set()
        kana_tiles_for_byte(b, tmp)
        add_tiles(tmp)
        i += 1
    # A page without any content after the last PAGE is still a page.
    if page.tokens or used != base_used or kanji or not pages:
        finish()
    return pages, True


_LIST_CACHE: dict[str, set[int]] = {}


def list_tile_set(tag: str) -> set[int]:
    if tag not in _LIST_CACHE:
        if tag == "menu":
            _LIST_CACHE[tag] = set(SUBMENU_TILES)
        elif tag == "item":
            _LIST_CACHE[tag] = set(item_name_tiles())
        elif tag == "savename":
            _LIST_CACHE[tag] = set(SAVENAME_TILES)
        elif tag == "party":
            _LIST_CACHE[tag] = set(party_name_tiles())
        else:
            _LIST_CACHE[tag] = set()
    return _LIST_CACHE[tag]


def message_list_tag(rec: Record) -> str:
    for label in rec.labels:
        if label in LIST_TAG_OVERRIDES:
            return LIST_TAG_OVERRIDES[label]
    stripped = rec.text.rstrip()
    visible = re.sub(r"<[^>]*>", "", stripped).rstrip()
    if stripped.endswith(("<END_NOWAIT>", "<WAIT>")):
        return "menu"
    if visible.endswith(("?", "\uff1f")):
        return "menu"
    return "none"


_KANA_CACHE: dict[str, set[int]] = {}


def message_kana_used(rec: Record) -> set[int]:
    """Tiles the message's own kana/table insertions draw (no scene extra)."""
    if rec.text not in _KANA_CACHE:
        cmap = code_map()
        data = compile_tokens(reflow(tokenize(rec.text)), cmap)
        pages, _ = page_from_bytes(data, set())
        used: set[int] = set()
        for page in pages:
            used |= page.used
        _KANA_CACHE[rec.text] = used - set(RESERVED_TILES)
    return _KANA_CACHE[rec.text]


MENU_TABLE_LO = 0x2DA1      # text_init's menu pointers: lo at $EDA1,x
MENU_TABLE_HI = 0x2DD1      # hi at $EDD1,x
MENU_COUNT = 0x30
NEAR_BEFORE = 0x300         # code bytes before a print site searched for menus
JUMP_AHEAD = 0x20           # code bytes after a JUMP target searched for menus
_MENU_SCRIPT_TILES: dict[int, set[int]] | None = None


def menu_script_tiles(menu: int) -> set[int]:
    """Fixed kana of menu script `menu` (its bytes up to the next script)."""
    global _MENU_SCRIPT_TILES
    if _MENU_SCRIPT_TILES is None:
        b15 = textdata.bank_bytes(15)
        starts = [(b15[MENU_TABLE_LO + x] | (b15[MENU_TABLE_HI + x] << 8)) - 0xC000
                  for x in range(MENU_COUNT)]
        ends = sorted(set(starts) | {MENU_TABLE_LO})
        _MENU_SCRIPT_TILES = {}
        for x, start in enumerate(starts):
            end = next((e for e in ends if e > start), None)
            if end is None or not 0x2948 <= start < MENU_TABLE_LO:
                continue            # not a script (entry $2F points at the table)
            _MENU_SCRIPT_TILES[x] = menu_stream_tiles(((start, end),))
    return _MENU_SCRIPT_TILES.get(menu, set())


_CODE_SCAN: dict[int, tuple[list[tuple[int, int]], list[tuple[int, int]]]] = {}


def code_scan(bank: int) -> tuple[list[tuple[int, int]], list[tuple[int, int]]]:
    """(menu opens, message prints) in an original code bank, as
    (offset, menu index) and (offset, message index) lists.

    Opens are ``ldx #menu`` + ``jsr`` text_init ($C9B8) or its two wait
    variants ($C990, $C999), and ``jsr $C99F`` (yes/no, menu $02).  Prints
    are ``jsr text_print_inline`` ($D10D) + the 16-bit message index.  Much
    of the menu code is undecoded data in the decomp, so the bytes are
    scanned.
    """
    if bank not in _CODE_SCAN:
        d = textdata.bank_bytes(bank)
        opens: list[tuple[int, int]] = []
        prints: list[tuple[int, int]] = []
        for i in range(len(d) - 4):
            if (d[i] == 0xA2 and d[i + 2] == 0x20 and d[i + 4] == 0xC9
                    and d[i + 3] in (0xB8, 0x90, 0x99)):
                opens.append((i, d[i + 1]))
            elif d[i] == 0x20 and d[i + 1] == 0x9F and d[i + 2] == 0xC9:
                opens.append((i, 0x02))
            elif d[i] == 0x20 and d[i + 1] == 0x0D and d[i + 2] == 0xD1:
                prints.append((i, d[i + 3] | (d[i + 4] << 8)))
        _CODE_SCAN[bank] = (opens, prints)
    return _CODE_SCAN[bank]


def message_label(idx: int) -> str:
    return f"b10_msg_{idx:03d}" if idx < 0x200 else f"b11_msg_{idx - 0x200:03d}"


def menus_near(bank: int, lo: int, hi: int) -> set[int] | None:
    found = {menu for off, menu in code_scan(bank)[0] if lo <= off < hi}
    return found or None


_JUMP_TARGETS: list[int] | None = None


def bank14_jump_targets() -> list[int]:
    """Bank-14 offsets that messages JUMP to (menu routine entries)."""
    global _JUMP_TARGETS
    if _JUMP_TARGETS is None:
        from kanji_common import DTX_FILES
        found: set[int] = set()
        for path in DTX_FILES:
            for rec in parse_dtx(path):
                for ptr in re.findall(r"<JUMP:([0-9A-Fa-f]{4})>", rec.text):
                    if 0x8000 <= int(ptr, 16) < 0xC000:
                        found.add(int(ptr, 16) - 0x8000)
        _JUMP_TARGETS = sorted(found)
    return _JUMP_TARGETS


def site_menus(bank: int, off: int) -> set[int] | None:
    """Menus that can be open at print site `off`: those opened in the
    NEAR_BEFORE bytes before it and, in bank 14, every menu opened since
    the menu routine entry (the nearest JUMP target) before it (revision 16:
    the partner shop opens its menu $1F at $92BE and prints 「...殿は隊列から
    外せないようですが」 at $9445)."""
    lo = off - NEAR_BEFORE
    if bank == 14:
        entries = [t for t in bank14_jump_targets() if t <= off]
        if entries:
            lo = min(lo, entries[-1])
    return menus_near(bank, lo, off)


def menu_context_tiles(rec: Record) -> set[int]:
    """Menu kana that can be on the band page while this message is shown.

    The game keeps a menu window up beside the text window while menu code
    prints its replies, and a message whose JUMP enters menu code leaves the
    window up while that code opens its menu (revision 16: the partner
    shop's のうりょく/くわえる/はずす/かいこ, garbled by 「...様、ご用件を
    ...」 and by the replies printed under it).

    - Printed by bank-14/15 code: the menus that code opened before the
      print (site_menus; the full submenu set if none).
    - JUMP into bank 14 or the fixed bank ($F9, high bit set): the menu the
      target opens in its first JUMP_AHEAD bytes (the full submenu set if
      none).
    - Bank-13 event code (prints, or JUMP high bit clear) opens only
      yes/no and きろく/よぶ next to a message.
    """
    labels = set(rec.labels)
    tiles: set[int] = set()
    for bank in (14, 15):
        for off, idx in code_scan(bank)[1]:
            if message_label(idx) in labels:
                menus = site_menus(bank, off)
                tiles |= (set().union(*(menu_script_tiles(m) for m in menus))
                          if menus else SUBMENU_TILES)
    if any(message_label(idx) in labels for _off, idx in code_scan(13)[1]):
        tiles |= EVENT_MENU_TILES
    for ptr in re.findall(r"<JUMP:([0-9A-Fa-f]{4})>", rec.text):
        target = int(ptr, 16)
        if target >= 0x8000:
            # $8000-$BFFF: bank 14; $C000-$FFFF: the fixed bank
            bank, off = (15, target - 0xC000) if target >= 0xC000 else (14, target - 0x8000)
            menus = menus_near(bank, off, off + JUMP_AHEAD)
            tiles |= (set().union(*(menu_script_tiles(m) for m in menus))
                      if menus else SUBMENU_TILES)
        else:
            tiles |= EVENT_MENU_TILES
    return tiles


def menu_context(rec: Record) -> str:
    """Report tag: "sub" (bank-14/15 menu code), "event" (bank 13) or ""."""
    labels = set(rec.labels)
    banks: set[int] = set()
    for bank in (13, 14, 15):
        if any(message_label(idx) in labels for _off, idx in code_scan(bank)[1]):
            banks.add(bank)
    for ptr in re.findall(r"<JUMP:([0-9A-Fa-f]{4})>", rec.text):
        banks.add(14 if int(ptr, 16) >= 0x8000 else 13)
    return "sub" if banks & {14, 15} else "event" if 13 in banks else ""


def extra_for(rec: Record) -> set[int]:
    """Kana that must stay on the private band page for this message.

    Prompt lists keep their own kana on screen (list tags), and a message
    printed by or leading into menu code shares the band page with that
    code's menu window (menu_context_tiles).
    """
    tag = message_list_tag(rec)
    extra = set(list_tile_set(tag)) if tag != "none" else set()
    if tag != "savename":
        extra |= menu_context_tiles(rec)
    return extra


_EXPOSURE: dict[int, int] | None = None


def tile_exposure(tile: int) -> int:
    """How likely the game draws this kana tile on the band page while some
    message is shown: 0 only in messages, 1 name-entry grid only,
    2 fixed submenu kana, 3 runtime officer/item names (the lists that menu
    code draws, which no reservation covers).  Kanji take the least exposed
    free tiles first, so a window the compiler did not foresee keeps its
    kana unless the page is kanji-heavy."""
    global _EXPOSURE
    if _EXPOSURE is None:
        names = party_name_tiles() | item_name_tiles()
        _EXPOSURE = {}
        for t in range(128):
            _EXPOSURE[t] = (3 if t in names else 2 if t in SUBMENU_TILES
                            else 1 if t in NAME_GRID_TILES else 0)
    return _EXPOSURE[tile]


def page_line_count(page: Page) -> int:
    return max(len(page.line_codes_all or page.line_codes), len(page.line_used), 1)


def page_future_used(pages: list[Page], index: int) -> set[int]:
    """Kana that this page's kanji tiles must avoid.

    The runtime keeps the kanji of the last three visible lines active for
    the whole of the next page.  So a kanji on this page must avoid every
    kana of each later page that starts while one of this page's lines can
    still be on screen (fewer than three lines after this page's end).
    """
    used: set[int] = set(pages[index].used)
    lines_after = 0
    for page in pages[index + 1:]:
        if lines_after >= 3:
            break
        used |= page.used
        lines_after += page_line_count(page)
    return used


def assign_page_tiles(page: Page, extra: set[int], reserved_extra: set[int] | None = None) -> dict[int, tuple[int, int, int, int]] | None:
    """Assign four free kana tiles to every distinct kanji on the page."""
    if len(page.kanji_order) > MAX_PAGE_ENTRIES:
        return None
    if not page.kanji_order:
        return {}
    reserved = set(page.used) | set(extra) | set(reserved_extra or ())
    free = sorted((tile for tile in range(128) if tile not in reserved),
                  key=lambda tile: (tile_exposure(tile), tile))
    if len(free) < 4 * len(page.kanji_order) + PAGE_TILE_MARGIN:
        return None
    return {code: tuple(free[i * 4:i * 4 + 4])
            for i, code in enumerate(page.kanji_order)}


def page_lines(page: Page) -> list[tuple[set[int], list[int]]]:
    codes = page.line_codes_all or page.line_codes
    out = []
    for n in range(max(len(codes), len(page.line_used))):
        kana = set(page.line_used[n]) if n < len(page.line_used) else set()
        kanji = list(codes[n]) if n < len(codes) else []
        out.append((kana, kanji))
    return out


RELAXED_LABELS: set[str] = set()
# Each wait starts a fresh window (page_flip in the fixed bank clears the
# window after the wait), so a page shares tiles only with itself.
import os as _os
FRESH_PAGES = _os.environ.get("KANJI_FRESH_PAGES", "1") == "1"


def assign_pages_full(pages: list[Page], extra: set[int], relaxed: bool = False):
    """Assign kanji tiles page by page.

    Returns one (tiles, reserved, keep, clean) tuple per page:
    - ``tiles``: code -> four tiles, or None when the page does not fit;
    - ``keep``: kanji tiles on the (up to) three earlier lines still on
      screen when the page starts; they stay active;
    - ``clean``: this page's kana tiles that an earlier page of the message
      used as kanji; the runtime restores them before printing.
    Slots avoid this page's kana, every tile on the visible earlier lines,
    and the kana of the next three lines.
    """
    result = []
    history: list[tuple[set[int], set[int]]] = []   # (kana, kanji tiles) per line
    earlier_slots: set[int] = set()
    for i, page in enumerate(pages):
        visible = [] if FRESH_PAGES else history[-3:]
        carry: set[int] = set()
        keep: set[int] = set()
        for kana, kanji_tiles in visible:
            carry |= kanji_tiles if relaxed else (kana | kanji_tiles)
            keep |= kanji_tiles
        future = set(page.used) if FRESH_PAGES else page_future_used(pages, i)
        reserved_extra = carry | future
        tiles = assign_page_tiles(page, extra, reserved_extra)
        reserved = set(page.used) | extra | reserved_extra
        clean = {t for t in page.used if t in earlier_slots and t not in keep}
        result.append((tiles, reserved, keep, clean))
        if tiles is None:
            break
        for t4 in tiles.values():
            earlier_slots.update(t4)
        for kana, codes in page_lines(page):
            kt: set[int] = set()
            for code in codes:
                if code in tiles:
                    kt.update(tiles[code])
            history.append((kana, kt))
    return result


def assign_pages_with_reserved(
        pages: list[Page], extra: set[int], relaxed: bool = False
) -> list[tuple[dict[int, tuple[int, int, int, int]] | None, set[int]]]:
    return [(t, r) for t, r, _k, _c in assign_pages_full(pages, extra, relaxed)]


def assign_pages(pages: list[Page], extra: set[int], relaxed: bool = False) -> list[dict[int, tuple[int, int, int, int]] | None]:
    return [tiles for tiles, _ in assign_pages_with_reserved(pages, extra, relaxed)]


def page_token_width(tokens: list[str]) -> list[int]:
    """Cumulative kanji index at each <PAGE>/line boundary (for splitting)."""
    out = []
    k = 0
    for tok in tokens:
        if KANJI_RE.match(tok):
            k += 1
        out.append(k)
    return out


def split_failing_page(tokens: list[str], page_index: int) -> list[str]:
    """Insert a page break inside the failing page.

    Prefer an existing line boundary so the original line layout is kept.  If
    the page has no line boundary (for example a short name-heavy page), split
    at the token boundary closest to half of the page's kanji count and force
    a new line before the page break.
    """
    # Locate the token range for this page.
    bounds = [0]
    for i, tok in enumerate(tokens):
        if tok == "<PAGE>":
            bounds.append(i + 1)
    bounds.append(len(tokens) + 1)
    start = bounds[page_index]
    end = bounds[page_index + 1] - 1
    candidates = []
    k = 0
    for i in range(start, end):
        tok = tokens[i]
        if KANJI_RE.match(tok):
            k += 1
        if tok in ("<NL>", "<NL2>", "<WAIT>"):
            candidates.append((i, k))
    total = k
    if candidates:
        target = total // 2
        best = min(candidates, key=lambda x: abs(x[1] - target))
        out = list(tokens)
        out[best[0]] = "<PAGE>"
        return out
    if end - start < 2:
        raise RuntimeError("page is too dense but has no token boundary to split")
    counts = []
    k = 0
    for i in range(start, end):
        if KANJI_RE.match(tokens[i]):
            k += 1
        counts.append((i + 1, k))
    target = total // 2
    pos = min((p for p in counts if start < p[0] < end),
              key=lambda x: abs(x[1] - target), default=None)
    if pos is None:
        raise RuntimeError("page is too dense but has no token boundary to split")
    i = pos[0]
    return tokens[:i] + ["<NL2>", "<PAGE>"] + tokens[i:]


WIDTH_ISSUES: list[str] = []
SPLIT_COUNT = [0]


def line_width_issues(rec: "Record", data: bytes) -> list[str]:
    """Lines wider than the window: 18 cells, 17 after an indenting break
    ($FA <NL>, $FC <PAGE>).  Runtime names count 8 cells."""
    issues = []
    width, cap, line = 0, 18, 0
    i = 0
    while i < len(data):
        b = data[i]
        if b == 0xEE and i + 2 < len(data) and data[i + 1] >= 0xFB:
            # Pick: count variant A only ($EE $FE n then skips variant B);
            # $EE $FC n steps back n cells; $FB's name counts 5 (with its
            # の計, the 8 of a runtime name).
            if data[i + 1] == 0xFC:
                width -= data[i + 2]
            if data[i + 1] == 0xFB:
                width += 5
            i += {0xFF: 4, 0xFD: 3, 0xFC: 3, 0xFB: 3}.get(data[i + 1], 3 + data[i + 2])
            continue
        if 0xEC <= b <= 0xEE:
            width += 2
            i += 3 if b == 0xEE else 2
            continue
        if b in (0xEF, 0xF0, 0xF1, 0xF2):
            width += 8
            i += 2
            continue
        if 0xF3 <= b <= 0xF7:
            width += 8
            i += 1
            continue
        if b in (0xF8, 0xF9):
            ptr = data[i + 1] | (data[i + 2] << 8) if i + 2 < len(data) else 0
            width += NUMBER_CALLS.get(ptr, 8) if b == 0xF8 else 0
            i += 3
            continue
        if b >= 0xFA:
            if width > cap:
                issues.append(f"{rec.labels[0]} line {line}: {width} > {cap}")
            cap = 17 if b in (0xFA, 0xFC) else 18
            width = 0
            line += 1
            i += 1
            continue
        width += 1
        i += 1
    if width > cap:
        issues.append(f"{rec.labels[0]} line {line}: {width} > {cap}")
    return issues


def build() -> int:
    cmap = code_map()
    from kanji_common import MAX_GLYPHS
    if len(cmap) > MAX_GLYPHS:
        raise SystemExit(f"too many kanji: {len(cmap)} > {MAX_GLYPHS}")
    OUT.mkdir(parents=True, exist_ok=True)

    records: list[Record] = []
    index_rec: dict[tuple[int, int], Record] = {}
    from kanji_common import DTX_FILES
    for bank, path in zip((10, 11), DTX_FILES):
        for rec in parse_dtx(path):
            records.append(rec)
            for label in rec.labels:
                m = re.match(rf"^b{bank:02d}_msg_(\d{{3}})$", label)
                if m:
                    idx = int(m.group(1))
                    if idx >= BANK_INFO[bank]["count"]:
                        raise ValueError(f"{label}: bad index")
                    index_rec[(bank, idx)] = rec

    # Reflow and page-split until every page has enough free kana tiles.
    # A message whose visible earlier lines leave too few tiles even after
    # splitting falls back to carrying only the kanji tiles (listed in the
    # report as relaxed_labels).
    def fit(rec: Record, tokens: list[str], extra: set[int], relaxed: bool):
        for _ in range(60):
            data = compile_tokens(tokens, cmap)
            if not data:
                # An empty message record must still be a valid END stream;
                # a zero-length data area would make its stub point at the
                # next record.
                data = bytes((0xFF,))
            pages = page_from_bytes(data, extra)[0]
            assignments = assign_pages(pages, extra, relaxed)
            if len(assignments) == len(pages) and all(t is not None for t in assignments):
                return data, pages, assignments
            failed = None
            for i, tiles in enumerate(assignments):
                if tiles is None:
                    failed = i
                    break
            if failed is None:
                failed = min(len(pages) - 1, len(assignments))
            token_pages = split_pages(tokens)
            if failed >= len(token_pages):
                failed = len(token_pages) - 1
            tokens = split_failing_page(tokens, failed)
            SPLIT_COUNT[0] += 1
        raise RuntimeError(f"{rec.labels[:1]}: could not fit after 60 splits")

    for rec in records:
        extra = extra_for(rec)
        tokens = reflow(tokenize(rec.text))
        rec.relaxed = False
        try:
            rec.data, rec.pages, page_tiles = fit(rec, tokens, extra, False)
        except RuntimeError:
            rec.relaxed = True
            RELAXED_LABELS.update(rec.labels[:1])
            rec.data, rec.pages, page_tiles = fit(rec, tokens, extra, True)

        WIDTH_ISSUES.extend(line_width_issues(rec, rec.data))
        full = assign_pages_full(rec.pages, extra, rec.relaxed)
        page_blobs = []
        for page, (tiles, _r, keep, clean) in zip(rec.pages, full):
            keep_l = sorted(t for t in keep if t < 0x80)
            clean_l = sorted(t for t in clean if t < 0x80)
            blob = bytearray((len(keep_l),)) + bytes(keep_l)
            blob += bytes((len(clean_l),)) + bytes(clean_l)
            # Bits 5-6: the page's runtime officer names (up to 3), for
            # which the battle's pool reserves 3 slots each (the overlay's
            # pool_need; KNAME_F4-F7 put the names there).
            blob.append(len(page.kanji_order) | (min(page.names, 3) << 5))
            for code in page.kanji_order:
                t4 = tiles[code]
                if any(t >= 0x80 for t in t4):
                    raise SystemExit(f"{rec.labels[:1]}: tile >= $80 in page")
                blob += bytes((code & 0xFF, code >> 8, *t4))
            page_blobs.append(bytes(blob))
        if len(page_blobs) > MAX_PAGES:
            raise SystemExit(f"message has {len(page_blobs)} pages > {MAX_PAGES}")
        kana = bytearray(16)
        for page in rec.pages:
            for t in page.used:
                if 0 <= t < 0x80:
                    kana[t >> 3] |= 0x80 >> (t & 7)
        # Byte 0: the page count; bit 5 (META_WIN, kanji.inc) marks a
        # victory message: in a battle the overlay then gives the pool the
        # portrait tiles $80-$A3 (no portrait after the win).
        if len(page_blobs) >= META_WIN:
            raise SystemExit(f"{rec.labels[:1]}: {len(page_blobs)} pages "
                             f"(page count bit 5 is META_WIN)")
        count = len(page_blobs)
        if set(rec.labels) & WIN_LABELS:
            count |= META_WIN
        rec.meta_blob = (bytes((count,)) + bytes(kana)
                         + b"".join(page_blobs))

    # Deduplicate identical message streams and page assignments.
    canon: dict[tuple[bytes, bytes], Record] = {}
    for rec in records:
        key = (rec.data, rec.meta_blob)
        if key not in canon:
            canon[key] = rec
    unique = list(canon.values())

    # Pack every unique message and its page records into a text bank.  The
    # overlay is identical at $BC00 in every bank.
    overlay_path = OUT / "kanji_overlay_padded.bin"
    if not overlay_path.exists():
        raise SystemExit("missing kanji_overlay_padded.bin; assemble first")
    overlay = overlay_path.read_bytes()
    if len(overlay) != OVERLAY_SIZE:
        raise SystemExit(f"overlay padding is {len(overlay)} bytes, expected {OVERLAY_SIZE}")
    from kanji_common import GLYPHS_PER_BANK
    glyphs = (OUT / "kanji_font.bin").stat().st_size // 32
    glyph_banks = set(range(23, 23 + max(2, -(-glyphs // GLYPHS_PER_BANK))))
    need = sum(len(rec.data) + len(rec.meta_blob) for rec in unique)
    banks = list(TEXT_BANKS)
    for extra in TEXT_BANKS_EXTRA:
        if need <= len(banks) * TEXT_BANK_LIMIT * 0.97:
            break
        if extra not in glyph_banks:
            banks.append(extra)
    TEXT_BANKS[:] = banks
    bank_data = {b: bytearray(0x4000) for b in TEXT_BANKS}
    for b in TEXT_BANKS:
        bank_data[b][TEXT_BANK_LIMIT:TEXT_BANK_LIMIT + OVERLAY_SIZE] = overlay

    bank_index = 0
    off = 0
    for rec in unique:
        need = len(rec.data) + len(rec.meta_blob)
        if off + need > TEXT_BANK_LIMIT:
            bank_index += 1
            off = 0
        if bank_index >= len(TEXT_BANKS):
            raise SystemExit("text data exceeds banks 18-22")
        b = TEXT_BANKS[bank_index]
        rec.data_bank = b
        rec.data_addr = 0x8000 + off
        bank_data[b][off:off + len(rec.data)] = rec.data
        off += len(rec.data)
        rec.meta_addr = 0x8000 + off
        bank_data[b][off:off + len(rec.meta_blob)] = rec.meta_blob
        off += len(rec.meta_blob)

    for rec in records:
        c = canon[(rec.data, rec.meta_blob)]
        rec.data_bank = c.data_bank
        rec.data_addr = c.data_addr
        rec.meta_addr = c.meta_addr
    message_map = {}
    for rec in records:
        for label in rec.labels:
            message_map[label] = [rec.data_bank, rec.data_addr]
    (OUT / "message_map.json").write_text(json.dumps(message_map, indent=2),
                                          encoding="utf-8")

    # Build banks 10/11 pointer tables and per-message F8 trampolines.
    original = textdata.prg()
    far_stub = far_stub_addr()
    trampoline_path = OUT / "trampoline.bin"
    if not trampoline_path.exists():
        raise SystemExit("missing trampoline.bin; assemble it first")
    trampoline = trampoline_path.read_bytes()
    if len(trampoline) > 0x100:
        raise SystemExit(f"trampoline is {len(trampoline)} bytes, max 256")
    for bank in (10, 11):
        info = BANK_INFO[bank]
        count = info["count"]
        start = DATA_START[bank]
        data_area = bytearray()
        stub_addr: dict[tuple[bytes, bytes], int] = {}
        used: list[Record] = []
        seen: set[tuple[bytes, bytes]] = set()
        for i in range(count):
            rec = index_rec.get((bank, i))
            if rec is None:
                raise SystemExit(f"bank {bank}: missing index {i}")
            key = (rec.data, rec.meta_blob)
            if key not in seen:
                seen.add(key)
                used.append(rec)
        for rec in used:
            key = (rec.data, rec.meta_blob)
            stub_addr[key] = 0x8000 + start + len(data_area)
            if rec.data and rec.data[0] == 0xF9:
                # A message that is only a JUMP (event code in bank 13/14):
                # its original three bytes here, no far stub.  The engine
                # tests $F9 only at a line's start ($D160); behind a stub the
                # overlay resumes inside the line ($D250), and the jump's
                # bytes printed as text (b11_msg_105, 2026-11-13).
                data_area += rec.data[:3]
                continue
            data_area += bytes((0xF8, far_stub & 0xFF, far_stub >> 8,
                                rec.data_bank,
                                rec.data_addr & 0xFF, rec.data_addr >> 8,
                                rec.meta_addr & 0xFF, rec.meta_addr >> 8))
        if start + len(data_area) > 0x4000:
            raise SystemExit(f"bank {bank}: stubs overflow: {start + len(data_area):X}")

        orig = original[bank * 0x4000:(bank + 1) * 0x4000]
        out = bytearray(orig)
        lo = bytearray()
        hi = bytearray()
        for i in range(count):
            rec = index_rec.get((bank, i))
            a = stub_addr[(rec.data, rec.meta_blob)]
            lo.append(a & 0xFF)
            hi.append(a >> 8)
        out[info["lo"]:info["lo"] + count] = lo
        out[info["hi"]:info["hi"] + count] = hi
        out[start:start + len(data_area)] = data_area
        toff = TRAMPOLINE_ADDR - 0x8000
        out[toff:toff + len(trampoline)] = trampoline
        (OUT / f"bank{bank:02d}.bin").write_bytes(bytes(out))
        print(f"bank {bank}: {len(used)} stubs, {len(data_area)} bytes "
              f"at ${start:04X}")

    for b in TEXT_BANKS:
        (OUT / f"bank{b:02d}.bin").write_bytes(bytes(bank_data[b]))

    # Report / debug dump
    all_pages = []
    min_free = 128
    min_free_with_kanji = 128
    max_slots = 0
    over_capacity = 0
    reservation_sizes = []
    for rec in unique:
        extra = extra_for(rec)
        pages = page_from_bytes(rec.data, extra)[0]
        assignments = assign_pages_with_reserved(pages, extra,
                                                 getattr(rec, "relaxed", False))
        for page, (tiles, reserved) in zip(pages, assignments):
            if tiles is None:
                over_capacity += 1
                continue
            reservation_sizes.append(len(reserved))
            free = 128 - len(reserved) - 4 * len(page.kanji_order)
            min_free = min(min_free, free)
            if page.kanji_order:
                min_free_with_kanji = min(min_free_with_kanji, free)
            max_slots = max(max_slots, len(page.kanji_order))
            all_pages.append(page)

    tags = {rec.labels[0]: message_list_tag(rec) for rec in unique if rec.labels}
    report = {
        "inventory": len(cmap),
        "messages": len(unique),
        "pages": len(all_pages),
        "max_page_slots": max_slots,
        "min_free_static": min_free,
        "min_free_with_kanji": min_free_with_kanji,
        "pages_over_capacity": over_capacity,
        "reserved_count": len(RESERVED_TILES),
        "reserved_tiles": sorted(RESERVED_TILES),
        "scene_borrow_tiles": sorted(SCENE_BORROW),
        "scene_borrow_labels": len(SCENE_BORROW_BY_LABEL),
        "scene_borrow_surveyed": sorted(SCENE_BORROW_BY_LABEL),
        "scene_fallback_tiles": len(SCENE_FALLBACK),
        "reservation_sizes": {
            "min": min(reservation_sizes, default=0),
            "max": max(reservation_sizes, default=0),
            "avg": round(sum(reservation_sizes) / len(reservation_sizes), 1)
            if reservation_sizes else 0,
        },
        "menu_stream_tiles": len(MENU_TILES),
        "submenu_tiles": len(SUBMENU_TILES - RESERVED_TILES),
        "event_menu_tiles": len(EVENT_MENU_TILES - RESERVED_TILES),
        "menu_context": {ctx or "none": sum(1 for rec in unique if menu_context(rec) == ctx)
                         for ctx in ("", "sub", "event")},
        "menu_context_conflicts": sorted(
            rec.labels[0] for rec in unique if rec.labels and any(
                t in menu_context_tiles(rec)
                for tiles in assign_pages(page_from_bytes(rec.data, extra_for(rec))[0],
                                          extra_for(rec), getattr(rec, "relaxed", False))
                if tiles for t4 in tiles.values() for t in t4)),
        "party_name_tiles": len(party_name_tiles()),
        "item_name_tiles": len(item_name_tiles()),
        "list_tags": {tag: sum(1 for value in tags.values() if value == tag)
                      for tag in ("none", "menu", "party", "item", "savename")},
        "max_meta_bytes": max((len(rec.meta_blob) for rec in unique), default=0),
        "max_meta_pages": max((rec.meta_blob[0] for rec in unique), default=0),
        "data_banks": sorted({rec.data_bank for rec in unique}),
        "overlay_bytes": len(overlay),
        "relaxed_labels": sorted(RELAXED_LABELS),
        "width_issues": len(WIDTH_ISSUES),
        "split_pages": SPLIT_COUNT[0],
    }
    (OUT / "kanji_width_issues.txt").write_text(chr(10).join(WIDTH_ISSUES) + chr(10), encoding="utf-8")
    (OUT / "kanji_text_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if max_slots > MAX_PAGE_ENTRIES:
        raise RuntimeError(f"page needs {max_slots} entries; limit is {MAX_PAGE_ENTRIES}")
    if over_capacity:
        raise RuntimeError(f"{over_capacity} pages do not fit after splitting")
    if report["menu_context_conflicts"]:
        raise RuntimeError(f"kanji on menu kana: {report['menu_context_conflicts'][:8]}")
    print(json.dumps(report, indent=2))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["build"], nargs="?", default="build")
    ap.parse_args()
    return build()


if __name__ == "__main__":
    raise SystemExit(main())
