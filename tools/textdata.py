#!/usr/bin/env python3
"""Parsing and editable text codec for the two message banks.

The game stores messages as a split pointer table plus a byte stream.

* Bytes ``$00-$7F`` select an 8x8 font tile directly.
* Bytes ``$80-$EE`` select a tile and add a dakuten/handakuten mark:
  the low seven bits are the base tile, and the top row is replaced by
  the dakuten (``$72``) or handakuten (``$73``) tile.  For handakuten
  codes the base tile is shifted down by ten tiles, which gives
  ``$E2-$E6`` = パピプペポ and ``$E7-$EB`` = ぱぴぷぺぽ.
* Bytes ``$EF-$FF`` are controls (word/place/item/name insertions,
  line breaks, page breaks, wait and end markers).

The codec maps every representable glyph to a Unicode character, expands
the word tables into readable ``<WORD:xx=...>`` style tokens, and leaves
anything that cannot be represented as an explicit ``<XX>`` token.  Every
byte therefore round-trips exactly.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROM_PATH = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"

# Per-bank table geometry.
BANK_INFO = {
    10: {"count": 488, "lo": 0x0000, "hi": 0x0200, "data": 0x03E8, "tail": 0x3DD3},
    11: {"count": 384, "lo": 0x0000, "hi": 0x0200, "data": 0x0380, "tail": 0x33F0},
}

# Reading order of assets/fonts/kana_8x8.png.  Each row is 16 tiles.
# The <...> entries are frame/tab tiles, not printable characters.
# Tile $78 is a small dot at mid height, used (nearly) only in ellipses:
# "." in the text ("-" until 2026-11-17, the user's correction).
FONT_ROWS = [
    "０１２３４５６７８９　<FRAME_LB><FRAME_TOP><FRAME_BOT>＊★",
    "かきくけこさしすせそたちつてとな",
    "にぬねのマメモユヨまみむめもやゆ",
    "よらりるれろわをんゃゅょっあいう",
    "えおアイウエオカキクケコサシスセ",
    "ソタチツテトナネハヒフミホはひふ",
    "へほラリルレロワンュョド金<FRAME_LT><FRAME_RT><FRAME_RB>",
    "▶▼゛゜ヤム「ッ.ー！？／<FRAME_L><FRAME_R>兵",
]

FRAME_BYTE_TO_TOKEN = {
    0x0B: "<FRAME_LB>",
    0x0C: "<FRAME_TOP>",
    0x0D: "<FRAME_BOT>",
    0x6D: "<FRAME_LT>",
    0x6E: "<FRAME_RT>",
    0x6F: "<FRAME_RB>",
    0x7D: "<FRAME_L>",
    0x7E: "<FRAME_R>",
}
FRAME_TOKEN_TO_BYTE = {v: k for k, v in FRAME_BYTE_TO_TOKEN.items()}

# Text drawn by the $F8 helper calls, where the target is known from the
# first-town transcript.  These are annotations only; the original pointer
# bytes are always preserved.
CALL_ANNOTATIONS = {
    0x21D0: "ソウジン",
    0x21D4: "ソウユウ",
    0x8262: "たからばこ",
    0xD565: "さくりゃく",
    0xD6F3: "すうじ",
    0x1F24: "すうじ",
}

# Control tokens.  Tokens with an inline operand use a colon form; the
# parser ignores anything after '=' (it is only an annotation for readers).
CONTROL_TOKENS = {
    "<NL>": 0xFA,
    "<NLNI>": 0xFB,
    "<PAGE>": 0xFC,
    "<PAGENI>": 0xFD,
    "<END_NOWAIT>": 0xFE,
    "<END>": 0xFF,
    "<NAME_F3>": 0xF3,
    "<NAME_F4>": 0xF4,
    "<NAME_F5>": 0xF5,
    "<NAME_F6>": 0xF6,
    "<NAME_F7>": 0xF7,
}
CONTROL_BYTE_TO_TOKEN = {v: k for k, v in CONTROL_TOKENS.items()}

DAKUTEN = {
    "か": "が", "き": "ぎ", "く": "ぐ", "け": "げ", "こ": "ご",
    "さ": "ざ", "し": "じ", "す": "ず", "せ": "ぜ", "そ": "ぞ",
    "た": "だ", "ち": "ぢ", "つ": "づ", "て": "で", "と": "ど",
    "は": "ば", "ひ": "び", "ふ": "ぶ", "へ": "べ", "ほ": "ぼ",
    "う": "ゔ",
    "カ": "ガ", "キ": "ギ", "ク": "グ", "ケ": "ゲ", "コ": "ゴ",
    "サ": "ザ", "シ": "ジ", "ス": "ズ", "セ": "ゼ", "ソ": "ゾ",
    "タ": "ダ", "チ": "ヂ", "ツ": "ヅ", "テ": "デ", "ト": "ド",
    "ハ": "バ", "ヒ": "ビ", "フ": "ブ", "ヘ": "ベ", "ホ": "ボ",
    "ウ": "ヴ",
}
HANDAKUTEN = {
    "は": "ぱ", "ひ": "ぴ", "ふ": "ぷ", "へ": "ぺ", "ほ": "ぽ",
    "ハ": "パ", "ヒ": "ピ", "フ": "プ", "ヘ": "ペ", "ホ": "ポ",
}

# Tile index -> printable character or frame token.
_TILE_CHARS: dict[int, str] = {}
for _row, _text in enumerate(FONT_ROWS):
    _i = 0
    _code = _row * 16
    while _i < len(_text):
        if _text[_i] == "<":
            _j = _text.index(">", _i)
            _tile = _text[_i:_j + 1]
            _i = _j + 1
        else:
            _tile = _text[_i]
            _i += 1
        _TILE_CHARS[_code] = _tile
        _code += 1
    assert _code == _row * 16 + 16

BYTE_TO_CHAR: dict[int, str] = {}
CHAR_TO_BYTE: dict[str, int] = {}


def _add_direct(code: int, ch: str) -> None:
    if ch.startswith("<"):
        return
    BYTE_TO_CHAR[code] = ch
    if ch not in CHAR_TO_BYTE:
        CHAR_TO_BYTE[ch] = code


for _code, _ch in _TILE_CHARS.items():
    _add_direct(_code, _ch)

# Add the dakuten/handakuten composed glyphs.
for _code in range(0x80, 0xEF):
    _base_code = _code & 0x7F
    if _base_code >= 0x62:
        _base_code -= 0x0A
        _table = HANDAKUTEN
    else:
        _table = DAKUTEN
    _base_char = _TILE_CHARS.get(_base_code)
    if not _base_char or _base_char.startswith("<"):
        continue
    _voiced = _table.get(_base_char)
    if _voiced is None:
        continue
    BYTE_TO_CHAR[_code] = _voiced
    if _voiced not in CHAR_TO_BYTE:
        CHAR_TO_BYTE[_voiced] = _code

# Convenience aliases for editors that type ASCII spaces/digits.
CHAR_TO_BYTE.setdefault(" ", 0x0A)
for _i, _ch in enumerate("0123456789"):
    CHAR_TO_BYTE.setdefault(_ch, _i)


def prg() -> bytes:
    global _PRG
    try:
        return _PRG
    except NameError:
        _PRG = ROM_PATH.read_bytes()[16:]
        return _PRG


def bank_bytes(bank: int) -> bytes:
    return prg()[bank * 0x4000:(bank + 1) * 0x4000]


@dataclass
class Record:
    start: int          # CPU address in the bank
    data: bytes
    indices: list[int]  # table indices that point here


@dataclass
class TextBank:
    bank: int
    count: int
    data_start: int
    tail_start: int
    records: list[Record]
    index_labels: list[str]

    def label(self, index: int) -> str:
        return f"b{self.bank:02d}_msg_{index:03d}"

    def index_symbol(self, index: int) -> str:
        return f"b{self.bank:02d}_msg_index_{index:03d}"

    def index_value(self, index: int) -> int:
        return index if self.bank == 10 else 0x0200 + index


def parse_bank(bank: int) -> TextBank:
    info = BANK_INFO[bank]
    b = bank_bytes(bank)
    count = info["count"]
    ptrs = [b[info["hi"] + i] << 8 | b[info["lo"] + i] for i in range(count)]
    by_addr: dict[int, list[int]] = {}
    for i, p in enumerate(ptrs):
        by_addr.setdefault(p, []).append(i)
    addrs = sorted(by_addr)
    tail_start = 0x8000 + info["tail"]
    records = []
    for j, addr in enumerate(addrs):
        end = addrs[j + 1] if j + 1 < len(addrs) else tail_start
        records.append(Record(addr, b[addr - 0x8000:end - 0x8000], by_addr[addr]))
    labels = [f"b{bank:02d}_msg_{i:03d}" for i in range(count)]
    return TextBank(bank, count, 0x8000 + info["data"], tail_start, records, labels)


# ---------------------------------------------------------------------------
# Word tables referenced by controls.

_DICTIONARY: dict[int, bytes] | None = None
_PLACES: dict[int, bytes] | None = None
_ITEMS: dict[int, bytes] | None = None


def _read_table(bank: int, lo: int, hi: int, count: int,
                skip: int = 0) -> dict[int, bytes]:
    b = bank_bytes(bank)
    out: dict[int, bytes] = {}
    for i in range(count):
        p = b[hi + i] << 8 | b[lo + i]
        if not (0x8000 <= p < 0xC000):
            continue
        off = p - 0x8000 + skip
        end = b.find(b"\xff", off)
        if end < 0:
            continue
        out[i] = b[off:end]
    return out


def dictionary_entries() -> dict[int, bytes]:
    """F0 xx: bank 13 split table at $B700/$B800, strings at $B900."""
    global _DICTIONARY
    if _DICTIONARY is None:
        _DICTIONARY = _read_table(13, 0x3700, 0x3800, 256)
    return _DICTIONARY


def place_entries() -> dict[int, bytes]:
    """EF xx: bank 12 split table at $A100/$A140 (used entries $60-$7F)."""
    global _PLACES
    if _PLACES is None:
        _PLACES = _read_table(12, 0x2100, 0x2140, 256)
    return _PLACES


def item_entries() -> dict[int, bytes]:
    """F1 xx: bank 12 split table at $A3C8/$A438; strings skip 2 bytes."""
    global _ITEMS
    if _ITEMS is None:
        _ITEMS = _read_table(12, 0x23C8, 0x2438, 256, skip=2)
    return _ITEMS


def _annotate(data: bytes) -> str:
    """Return a short, token-safe rendering of a referenced string."""
    out: list[str] = []
    i = 0
    while i < len(data):
        b = data[i]
        if b == 0xFF:
            break
        if b == 0xF0 and i + 1 < len(data):
            i += 2
            continue
        if b in (0xEF, 0xF1, 0xF2) and i + 1 < len(data):
            i += 2
            continue
        if b in (0xF8, 0xF9) and i + 2 < len(data):
            i += 3
            continue
        if b in (0xF3, 0xF4, 0xF5, 0xF6, 0xF7,
                 0xFA, 0xFB, 0xFC, 0xFD, 0xFE):
            i += 1
            continue
        ch = BYTE_TO_CHAR.get(b)
        if ch is not None:
            out.append(ch)
        i += 1
    text = "".join(out).strip()
    for bad in "<>=":
        text = text.replace(bad, "")
    return text[:48]


def encode_record(data: bytes) -> str:
    """Encode one message stream as editable DTX text."""
    out: list[str] = []
    i = 0
    while i < len(data):
        b = data[i]

        if b == 0xF0 and i + 1 < len(data):
            idx = data[i + 1]
            ann = _annotate(dictionary_entries().get(idx, b""))
            out.append(f"<WORD:{idx:02X}={ann}>" if ann else f"<WORD:{idx:02X}>")
            i += 2
            continue
        if b == 0xEF and i + 1 < len(data):
            idx = data[i + 1]
            ann = _annotate(place_entries().get(idx, b""))
            out.append(f"<PLACE:{idx:02X}={ann}>" if ann else f"<PLACE:{idx:02X}>")
            i += 2
            continue
        if b == 0xF1 and i + 1 < len(data):
            idx = data[i + 1]
            ann = _annotate(item_entries().get(idx, b""))
            out.append(f"<ITEM:{idx:02X}={ann}>" if ann else f"<ITEM:{idx:02X}>")
            i += 2
            continue
        if b == 0xF2 and i + 1 < len(data):
            out.append(f"<NAME:{data[i + 1]:02X}>")
            i += 2
            continue
        if b == 0xF8 and i + 2 < len(data):
            ptr = data[i + 1] | (data[i + 2] << 8)
            ann = CALL_ANNOTATIONS.get(ptr)
            out.append(f"<CALL:{ptr:04X}={ann}>" if ann else f"<CALL:{ptr:04X}>")
            i += 3
            continue
        if b == 0xF9 and i + 2 < len(data):
            ptr = data[i + 1] | (data[i + 2] << 8)
            out.append(f"<JUMP:{ptr:04X}>")
            i += 3
            continue

        token = CONTROL_BYTE_TO_TOKEN.get(b)
        if token is not None:
            out.append(token)
            i += 1
            continue
        frame = FRAME_BYTE_TO_TOKEN.get(b)
        if frame is not None:
            out.append(frame)
            i += 1
            continue
        ch = BYTE_TO_CHAR.get(b)
        if ch is not None:
            # A few characters have more than one tile code (for example
            # ド is both $6B and $D5).  Keep the canonical code as a literal
            # character and spell the alternate as <XX:char> so the exact
            # original byte is preserved.
            if CHAR_TO_BYTE.get(ch) == b:
                out.append(ch)
            else:
                out.append(f"<{b:02X}:{ch}>")
        else:
            out.append(f"<{b:02X}>")
        i += 1
    return "".join(out)


def decode_record(text: str) -> bytes:
    """Compile editable DTX text back into message bytes."""
    out = bytearray()
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "<":
            j = text.find(">", i + 1)
            if j < 0:
                raise ValueError(f"unterminated token at offset {i}")
            token = text[i + 1:j]
            key = token.split("=", 1)[0].strip()
            if not key:
                raise ValueError(f"empty token at offset {i}")
            i = j + 1

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
            elif f"<{key}>" in CONTROL_TOKENS:
                out.append(CONTROL_TOKENS[f"<{key}>"])
            elif f"<{key}>" in FRAME_TOKEN_TO_BYTE:
                out.append(FRAME_TOKEN_TO_BYTE[f"<{key}>"])
            elif ":" in key:
                # <XX:char> is an alternate tile code for a character whose
                # canonical code is different (for example <D5:ド>).
                out.append(int(key.split(":", 1)[0], 16))
            else:
                out.append(int(key, 16))
            continue

        if ch in CHAR_TO_BYTE:
            out.append(CHAR_TO_BYTE[ch])
            i += 1
        elif ch == " ":
            out.append(0x0A)
            i += 1
        elif "0" <= ch <= "9":
            out.append(ord(ch) - ord("0"))
            i += 1
        else:
            raise ValueError(f"character {ch!r} at offset {i} has no tile code; use <XX>")
    return bytes(out)


@dataclass
class InlineRef:
    bank: int          # PRG bank containing the JSR
    inline_addr: int   # CPU address of the 2-byte inline index
    table_bank: int    # 10 or 11
    index: int
    word: int

    @property
    def index_symbol(self) -> str:
        return f"b{self.table_bank:02d}_msg_index_{self.index:03d}"

    @property
    def message_label(self) -> str:
        return f"b{self.table_bank:02d}_msg_{self.index:03d}"


def inline_refs(traces: dict) -> dict[tuple[int, int], InlineRef]:
    """Find JSR text_print_inline call sites and decode their inline index."""
    refs: dict[tuple[int, int], InlineRef] = {}
    for bank in range(16):
        insn = traces[bank][0]
        b = bank_bytes(bank)
        for addr, ins in insn.items():
            if not (ins.mnemonic == "jsr" and ins.mode == "abs" and ins.value == 0xD10D):
                continue
            inline = addr + ins.size
            base = 0xC000 if bank == 15 else 0x8000
            off = inline - base
            if off < 0 or off + 1 >= len(b):
                continue
            word = b[off] | (b[off + 1] << 8)
            if word < 0x200:
                table_bank, index = 10, word
                if index >= BANK_INFO[10]["count"]:
                    continue
            elif 0x200 <= word < 0x200 + BANK_INFO[11]["count"]:
                table_bank, index = 11, word - 0x200
            else:
                continue
            refs[(bank, inline)] = InlineRef(bank, inline, table_bank, index, word)
    return refs


def message_labels() -> dict[int, dict[int, str]]:
    """Map bank -> address -> first message label, for Mesen labels."""
    out: dict[int, dict[int, str]] = {10: {}, 11: {}}
    for bank in (10, 11):
        tb = parse_bank(bank)
        addr = tb.data_start
        for rec in tb.records:
            out[bank][addr] = tb.label(rec.indices[0])
            addr += len(rec.data)
    return out
