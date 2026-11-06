#!/usr/bin/env python3
"""Compile the proofread kanji draft into the expanded text banks.

The original text engine keeps its index scheme (index < $200 -> bank 10,
otherwise bank 11).  In the kanji target those banks contain only pointer
tables plus 8-byte trampolines.  Each trampoline calls the far-text loader in
bank 13, which switches to one of banks 18-21 and continues in the patched
fixed bank.

Page records in banks 10/11 give the runtime a per-page kanji slot map:
    count byte
    count * (code_lo, code_hi, base_tile, uploaded_flag)
The compiler allocates four consecutive CHR tiles per distinct kanji from
tiles that the page's kana text does not use.
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
FAR_LOADER = 0x8317          # bank 13 routine entry (and stub operand $0317)
MAX_PAGES = 16
RESERVED_TILES = {
    0x0A, 0x71, 0x72, 0x73,
    0x7D, 0x7E, 0x6D, 0x6E, 0x6F,
    0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
}
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


def name_tiles() -> set[int]:
    b12 = textdata.bank_bytes(12)
    used: set[int] = set()
    for i in range(256):
        p = b12[0x2800 + i] | (b12[0x2900 + i] << 8)
        if not (0x8000 <= p < 0xC000):
            continue
        off = p - 0x8000 + 0x14
        end = b12.find(b"\xff", off)
        if end < 0:
            continue
        try:
            s = textdata.encode_record(b12[off:end])
        except Exception:
            continue
        for ch in re.sub(r"<[^>]*>", "", s):
            b = char_to_byte(ch)
            if b is not None:
                kana_tiles_for_byte(b, used)
    return used


NAME_TILES = name_tiles()


def call_tiles(ptr: int) -> set[int]:
    used: set[int] = set()
    s = textdata.CALL_ANNOTATIONS.get(ptr, "")
    for ch in s:
        b = char_to_byte(ch)
        if b is not None:
            kana_tiles_for_byte(b, used)
    return used


def page_from_bytes(data: bytes) -> tuple[list[Page], bool]:
    """Split one compiled message into pages and collect tile demand."""
    pages: list[Page] = []
    page = Page([])
    used: set[int] = set(RESERVED_TILES)
    kanji: list[int] = []
    has_name = False
    i = 0

    def finish() -> None:
        nonlocal page, used, kanji, has_name
        if has_name:
            used |= NAME_TILES
        page.used = set(used)
        page.kanji_order = list(kanji)
        pages.append(page)
        page = Page([])
        used = set(RESERVED_TILES)
        kanji = []
        has_name = False

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
                    s = textdata.encode_record(table().get(idx, b""))
                except Exception:
                    s = ""
                for ch in re.sub(r"<[^>]*>", "", s):
                    tb = char_to_byte(ch)
                    if tb is not None:
                        kana_tiles_for_byte(tb, used)
            else:
                has_name = True
            i += 2
            continue
        if 0xF3 <= b <= 0xF7:
            has_name = True
            i += 1
            continue
        if b in (0xF8, 0xF9) and i + 2 < len(data):
            ptr = data[i + 1] | (data[i + 2] << 8)
            if b == 0xF8:
                used |= call_tiles(ptr)
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
    if page.tokens or used != set(RESERVED_TILES) or kanji or has_name or not pages:
        finish()
    return pages, True


def allocate(page: Page) -> bool:
    free = [t for t in range(128) if t not in page.used]
    page.entries = []
    for code in page.kanji_order:
        if len(free) < 4:
            return False
        tiles = free[:4]
        del free[:4]
        page.entries.append((code, tuple(tiles)))
    return True


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
    """Replace a line-ending token inside the failing page with <PAGE>."""
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
    if not candidates:
        raise RuntimeError("page is too dense but has no line boundary to split")
    total = k
    target = total // 2
    best = min(candidates, key=lambda x: abs(x[1] - target))
    out = list(tokens)
    out[best[0]] = "<PAGE>"
    return out


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

    # Reflow and page-split until every page fits.
    for rec in {id(r): r for r in records}.values():
        tokens = reflow(tokenize(rec.text))
        for _ in range(20):
            pages_tokens = split_pages(tokens)
            ok = True
            for p in pages_tokens:
                data = compile_tokens(p, cmap)
                pages, _ = page_from_bytes(data + b"\xff")
                for page in pages[:-1] if len(pages) > 1 else pages:
                    if not allocate(page):
                        ok = False
                        break
                if not ok:
                    break
            if ok:
                rec.data = compile_tokens(tokens, cmap)
                break
            # find the first failing page and split it
            failed = None
            for pi, p in enumerate(pages_tokens):
                data = compile_tokens(p, cmap)
                pages, _ = page_from_bytes(data + b"\xff")
                if any(not allocate(page) for page in pages):
                    failed = pi
                    break
            if failed is None:
                raise RuntimeError("internal split failure")
            tokens = split_failing_page(tokens, failed)
        else:
            raise RuntimeError("could not fit message after 20 splits")
        rec.pages = [Page(p) for p in split_pages(tokens)]

    # Pack unique message streams into banks 18-21.
    for rec in records:
        if not rec.data:
            rec.data = b"\xff"
    unique: dict[bytes, Record] = {}
    for rec in records:
        if rec.data not in unique:
            unique[rec.data] = rec
    bank = 18
    off = 0
    for rec in unique.values():
        if off + len(rec.data) > 0x4000:
            bank += 1
            off = 0
        if bank > 21:
            raise SystemExit("text data exceeds banks 18-21")
        rec.data_bank = bank
        rec.data_addr = 0x8000 + off
        off += len(rec.data)
    canon = {data: rec for data, rec in unique.items()}
    for rec in records:
        c = canon[rec.data]
        rec.data_bank = c.data_bank
        rec.data_addr = c.data_addr

    bank_data = {b: bytearray(0x4000) for b in range(18, 22)}
    for rec in unique.values():
        base = (rec.data_bank - 18) * 0x4000 + (rec.data_addr - 0x8000)
        flat = bytearray().join([bank_data[18 + j] for j in range(4)])
        flat[base:base + len(rec.data)] = rec.data
        for j in range(4):
            bank_data[18 + j][:] = flat[j * 0x4000:(j + 1) * 0x4000]

    # Build page records per unique message.
    meta: dict[int, tuple[int, bytes]] = {}
    for rec in unique.values():
        page_blobs = []
        pages = page_from_bytes(rec.data)[0]
        for page in pages:
            if not allocate(page):
                raise RuntimeError("page did not fit after splitting")
            blob = bytearray((len(page.entries),))
            for code, tiles in page.entries:
                blob += bytes((code & 0xFF, code >> 8, tiles[0], tiles[1], tiles[2], tiles[3]))
            page_blobs.append(bytes(blob))
        payload = b"".join(page_blobs)
        if len(page_blobs) > MAX_PAGES:
            raise SystemExit(f"message has {len(page_blobs)} pages > {MAX_PAGES}")
        meta[id(rec)] = (len(page_blobs), payload)
    for rec in records:
        c = canon[rec.data]
        meta[id(rec)] = meta[id(c)]

    # Build banks 10/11.
    original = textdata.prg()
    for bank in (10, 11):
        info = BANK_INFO[bank]
        count = info["count"]
        start = DATA_START[bank]
        data_area = bytearray()
        stub_addr: dict[bytes, int] = {}
        # unique records used by this bank, in first-seen index order
        used_recs: list[Record] = []
        used_data: set[bytes] = set()
        for i in range(count):
            rec = index_rec.get((bank, i))
            if rec is not None and rec.data not in used_data:
                used_recs.append(rec)
                used_data.add(rec.data)
        meta_bank = 22 if bank == 10 else 23
        meta_area = bytearray()
        for rec in used_recs:
            stub_addr[rec.data] = 0x8000 + start + len(data_area)
            data_area += bytes((0xF8, FAR_LOADER & 0xFF, (FAR_LOADER >> 8) & 0x7F,
                                rec.data_bank,
                                rec.data_addr & 0xFF, rec.data_addr >> 8,
                                0, 0))  # meta pointer filled below
        for rec in used_recs:
            meta_addr = 0x8000 + len(meta_area)
            stub_off = stub_addr[rec.data] - (0x8000 + start)
            data_area[stub_off + 6] = meta_addr & 0xFF
            data_area[stub_off + 7] = meta_addr >> 8
            pages, payload = meta[id(rec)]
            meta_area += bytes((pages, len(payload) & 0xFF, (len(payload) >> 8) & 0xFF))
            meta_area += payload
        if start + len(data_area) > 0x4000:
            raise SystemExit(f"bank {bank}: stubs overflow: {start + len(data_area):X}")
        if len(meta_area) > 0x4000:
            raise SystemExit(f"metadata bank {meta_bank}: overflow: {len(meta_area):X}")

        # pointer tables + gap from the original bank
        orig = original[bank * 0x4000:(bank + 1) * 0x4000]
        out = bytearray(orig)
        lo = bytearray()
        hi = bytearray()
        for i in range(count):
            rec = index_rec.get((bank, i))
            if rec is None:
                raise SystemExit(f"bank {bank}: missing index {i}")
            a = stub_addr[rec.data]
            lo.append(a & 0xFF)
            hi.append(a >> 8)
        out[info["lo"]:info["lo"] + count] = lo
        out[info["hi"]:info["hi"] + count] = hi
        out[start:start + len(data_area)] = data_area
        (OUT / f"bank{bank:02d}.bin").write_bytes(bytes(out))

        md = bytearray(0x4000)
        md[:len(meta_area)] = meta_area
        (OUT / f"bank{meta_bank:02d}.bin").write_bytes(bytes(md))
        print(f"bank {bank}: stubs {len(data_area)} bytes at ${start:04X}; "
              f"metadata {len(meta_area)} bytes in bank {meta_bank}")

    for b in range(18, 22):
        (OUT / f"bank{b:02d}.bin").write_bytes(bytes(bank_data[b]))

    # Report / debug dump
    all_pages = []
    for r in unique.values():
        pages = page_from_bytes(r.data)[0]
        for p in pages:
            if not allocate(p):
                raise RuntimeError("page did not fit")
            all_pages.append(p)
    report = {
        "inventory": len(cmap),
        "messages": len(unique),
        "pages": len(all_pages),
        "max_page_slots": max((len(p.entries) for p in all_pages), default=0),
        "data_banks": sorted({r.data_bank for r in unique.values()}),
        "bank10_used": len((OUT / "bank10.bin").read_bytes()),
        "bank11_used": len((OUT / "bank11.bin").read_bytes()),
    }
    (OUT / "kanji_text_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["build"], nargs="?", default="build")
    ap.parse_args()
    return build()


if __name__ == "__main__":
    raise SystemExit(main())
