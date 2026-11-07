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

from kanji_common import code_map, inventory
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
FAR_STUB = 0xC63A            # fixed-bank far stub (F8 3A C6 trampoline)
MAX_PAGES = 32
MAX_PAGE_ENTRIES = 16
PAGE_TILE_MARGIN = 4       # keep a little CHR slack for unmeasured scene tiles
TEXT_BANKS = [18, 19, 20, 21, 22]
TEXT_BANK_LIMIT = 0x3800     # overlay occupies $B800-$BFFF
OVERLAY_SIZE = 0x800
SCENE_BORROW = set(range(0x42, 0x5C))  # measured oath-scene overwrite range
SCENE_BORROW_FILE = PLAN / "scene_borrow.tsv"


def load_scene_borrow() -> dict[str, set[int]]:
    table: dict[str, set[int]] = {}
    if not SCENE_BORROW_FILE.exists():
        return table
    for line in SCENE_BORROW_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        label, spec = line.split("\t")
        table[label] = set() if spec == "-" else {
            int(tile, 16) for tile in spec.split(",")}
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
CURSOR_TILES = {0x0A, 0x71, 0x72, 0x73}
DIGIT_TILES = set(range(0x0A))

# Inline bank-15 menu scripts.  They are redrawn after the message closes and
# the restore-at-exit hook puts the kana font back, so they are not part of the
# per-page reservation.  Kept for reporting and later conversion work.
MENU_REGIONS = ((0x2948, 0x2C00), (0x2C00, 0x2DA1))


def menu_stream_tiles() -> set[int]:
    b = textdata.bank_bytes(15)
    used: set[int] = set()
    for start, end in MENU_REGIONS:
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
# $6C (金) and $7F (兵) are used as field-map icons; never borrow them.
RESERVED_TILES = FRAME_TILES | CURSOR_TILES | DIGIT_TILES | {0x6C, 0x7F}


def extra_reserved(text: str) -> set[int]:
    """Tiles that stay on screen while this message is open.

    Question prompts leave the window up while the yes/no or choice menu is
    drawn, so the menu kana must not be stolen by kanji slots.
    """
    visible = re.sub(r"<[^>]*>", "", text).rstrip()
    if text.rstrip().endswith(("<END_NOWAIT>", "<WAIT>")):
        return set(MENU_TILES)
    if visible.endswith(("?", "？")):
        return set(MENU_TILES)
    return set()


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


KANJI_RE = re.compile(r"[\u3400-\u9fff\uf900-\ufaff]")
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


@dataclass
class Page:
    tokens: list[str]
    entries: list[tuple[int, int, int]] = field(default_factory=list)  # code, base
    used: set[int] = field(default_factory=set)
    kanji_order: list[int] = field(default_factory=list)


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
            ch = text[i]
            if ch == "\u3005" and out and KANJI_RE.match(out[-1]):
                # The original 8x8 font has no iteration mark; expanding it to
                # the previous kanji keeps the intended reading.
                out.append(out[-1])
            else:
                out.append(ch)
            i += 1
    return out


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
            out += bytes((0xEC + (code >> 8), code & 0xFF))
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
    i = 0

    def finish() -> None:
        nonlocal page, used, kanji
        page.used = set(used)
        page.kanji_order = list(kanji)
        pages.append(page)
        page = Page([])
        used = set(base_used)
        kanji = []

    while i < len(data):
        b = data[i]
        if 0xEC <= b <= 0xEE:
            if i + 1 >= len(data):
                break
            code = ((b - 0xEC) << 8) | data[i + 1]
            if code not in kanji:
                kanji.append(code)
            i += 2
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
                    used |= tiles_for_string(textdata.encode_record(table().get(idx, b"")))
                except Exception:
                    pass
            elif b == 0xF2:
                used |= name_tiles_for_index(idx)
            i += 2
            continue
        if b == 0xF3:
            used |= item_name_tiles()
            i += 1
            continue
        if 0xF4 <= b <= 0xF7:
            used |= party_name_tiles()
            i += 1
            continue
        if b in (0xF8, 0xF9) and i + 2 < len(data):
            if b == 0xF8:
                used |= call_tiles(data[i + 1] | (data[i + 2] << 8))
            else:
                # The original engine renders $F9 and both operand bytes as
                # cells; reserve the two operand tiles when they are glyphs.
                for x in (data[i + 1], data[i + 2]):
                    if x < 0xEC:
                        kana_tiles_for_byte(x, used)
            i += 3
            continue
        if b == 0xFC:
            finish()
            i += 1
            continue
        if b >= 0xFA:
            i += 1
            continue
        kana_tiles_for_byte(b, used)
        i += 1
    # A page without any content after the last PAGE is still a page.
    if page.tokens or used != base_used or kanji or not pages:
        finish()
    return pages, True


_LIST_CACHE: dict[str, set[int]] = {}


def list_tile_set(tag: str) -> set[int]:
    if tag not in _LIST_CACHE:
        if tag == "menu":
            _LIST_CACHE[tag] = set(MENU_TILES)
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


def extra_for(rec: Record) -> set[int]:
    tag = message_list_tag(rec)
    if tag != "none":
        return set(list_tile_set(tag))
    borrowed: set[int] = set()
    found = False
    for label in rec.labels:
        if label in SCENE_BORROW_BY_LABEL:
            found = True
            borrowed |= SCENE_BORROW_BY_LABEL[label]
    return borrowed if found else set(SCENE_BORROW)


def assign_page_tiles(page: Page, extra: set[int]) -> dict[int, tuple[int, int, int, int]] | None:
    """Assign four free kana tiles to every distinct kanji on the page."""
    if len(page.kanji_order) > MAX_PAGE_ENTRIES:
        return None
    reserved = set(page.used) | set(extra)
    free = [tile for tile in range(128) if tile not in reserved]
    if len(free) < 4 * len(page.kanji_order) + PAGE_TILE_MARGIN:
        return None
    return {code: tuple(free[i * 4:i * 4 + 4])
            for i, code in enumerate(page.kanji_order)}


def page_fits_static(page: Page, extra: set[int]) -> bool:
    return assign_page_tiles(page, extra) is not None


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


def build() -> int:
    cmap = code_map()
    if len(cmap) > 768:
        raise SystemExit(f"too many kanji: {len(cmap)}")
    OUT.mkdir(parents=True, exist_ok=True)

    records: list[Record] = []
    index_rec: dict[tuple[int, int], Record] = {}
    for bank, path in ((10, PLAN / "bank10_messages_kanji_fixed.dtx"),
                       (11, PLAN / "bank11_messages_kanji_fixed.dtx")):
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
    for rec in records:
        extra = extra_for(rec)
        tokens = reflow(tokenize(rec.text))
        for _ in range(60):
            pages_tokens = split_pages(tokens)
            failed = None
            for pi, p in enumerate(pages_tokens):
                data = compile_tokens(p, cmap)
                pages, _ = page_from_bytes(data + b"\xff", extra)
                if any(not page_fits_static(page, extra) for page in pages):
                    failed = pi
                    break
            if failed is None:
                break
            tokens = split_failing_page(tokens, failed)
        else:
            raise RuntimeError(f"{rec.labels[:1]}: could not fit after 60 splits")

        rec.data = compile_tokens(tokens, cmap)
        pages = page_from_bytes(rec.data, extra)[0]
        page_blobs = []
        for page in pages:
            tiles = assign_page_tiles(page, extra)
            if tiles is None:
                raise RuntimeError(f"{rec.labels[:1]}: page assignment failed")
            blob = bytearray((len(page.kanji_order),))
            for code in page.kanji_order:
                blob += bytes((code & 0xFF, code >> 8, *tiles[code]))
            page_blobs.append(bytes(blob))
        if len(page_blobs) > MAX_PAGES:
            raise SystemExit(f"message has {len(page_blobs)} pages > {MAX_PAGES}")
        rec.meta_blob = bytes((len(page_blobs),)) + b"".join(page_blobs)
        rec.pages = pages

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
            data_area += bytes((0xF8, FAR_STUB & 0xFF, FAR_STUB >> 8,
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
    for rec in unique:
        extra = extra_for(rec)
        pages = page_from_bytes(rec.data, extra)[0]
        for page in pages:
            tiles = assign_page_tiles(page, extra)
            if tiles is None:
                over_capacity += 1
                continue
            reserved = set(page.used) | extra
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
        "menu_stream_tiles": len(MENU_TILES),
        "party_name_tiles": len(party_name_tiles()),
        "item_name_tiles": len(item_name_tiles()),
        "list_tags": {tag: sum(1 for value in tags.values() if value == tag)
                      for tag in ("none", "menu", "party", "item", "savename")},
        "max_meta_bytes": max((len(rec.meta_blob) for rec in unique), default=0),
        "max_meta_pages": max((rec.meta_blob[0] for rec in unique), default=0),
        "data_banks": sorted({rec.data_bank for rec in unique}),
        "overlay_bytes": len(overlay),
    }
    (OUT / "kanji_text_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if max_slots > MAX_PAGE_ENTRIES:
        raise RuntimeError(f"page needs {max_slots} entries; limit is {MAX_PAGE_ENTRIES}")
    if over_capacity:
        raise RuntimeError(f"{over_capacity} pages do not fit after splitting")
    print(json.dumps(report, indent=2))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["build"], nargs="?", default="build")
    ap.parse_args()
    return build()


if __name__ == "__main__":
    raise SystemExit(main())
