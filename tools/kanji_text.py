#!/usr/bin/env python3
"""Compile the proofread kanji draft into the text chunks.

Each unique message is packed into one of the TEXT_CHUNKS 8 KiB text chunks
(kanji.inc: the 8 KiB banks TEXT_8K.., the 16 KiB banks 18-19), always read
at $A000-$BFFF; a message never crosses a chunk.  No metadata (2026-11-14:
the message engine scans each page's kanji at run time, kanji_msg.asm).
Banks 10/11 keep the original pointer tables and hold a 6-byte stub per
message:

    F8 <far_head lo/hi> <text chunk | $80: a victory message> <text addr lo/hi>

The F8 trampoline ($BF00 in banks 10/11) makes the message bank (the
message engine in hack bank 23's lower half, the chunk at R7) current and
enters the engine.

A page (between page breaks) may show at most MAX_PAGE_ENTRIES kanji, the
message engine's table; fit_tokens splits a page with more (none now).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

from kanji_common import KANJI_CALLS, KANJI_SUFFIX_CALLS, KANJI_TROOP_CALLS, code_map, inventory, officer_names
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
STUB_WIN = 0x80             # stub byte 3 bit 7: a victory message (kanji.inc MSG_WIN)
# b10_msg_059 「…との戦いに勝った」 (after the scripted battles' victory face),
# 061 / 062 (the rewards): the battle is won (kanji_msg.asm message_setup).
WIN_LABELS = {"b10_msg_059", "b10_msg_061", "b10_msg_062"}
MAX_PAGE_ENTRIES = 16       # kanji.inc MAX_PAGE_KANJI: REG_LO/HI 0-15
MAX_PAGE_NAMES = 3          # runtime officer names a page reserves pool slots for
# Message text codes (2026-11-13): $EC-$EF pos = a kanji (store bank 0-3),
# KCTL ctl ... = the kanji controls (kanji_msg.asm kanji_ctl; $EE before
# the kanji store).  $EF and $F0 were the original's place and word
# insertions, which the compiled text does not use.
KCTL = 0xF0
_KINC = (ROOT / "decomp" / "include" / "kanji.inc").read_text(encoding="utf-8")


def _kinc(name: str) -> int:
    """A kanji.inc constant: numbers ($hex, decimal) and constants joined
    by + and |, left to right."""
    m = re.search(rf"^{name}\s*=\s*([^;\n]+)", _KINC, re.M)
    if not m:
        raise SystemExit(f"kanji.inc: no {name}")
    value, op = 0, "+"
    for tok in re.findall(r"\$[0-9A-Fa-f]+|\d+|[A-Za-z_]\w*|[+|]", m.group(1)):
        if tok in "+|":
            op = tok
            continue
        v = (int(tok[1:], 16) if tok[0] == "$" else int(tok) if tok[0].isdigit()
             else _kinc(tok))
        value = value + v if op == "+" else value | v
    return value


# The text chunks (kanji.inc, 2026-11-14): 8 KiB banks TEXT_8K..+TEXT_CHUNKS-1,
# read at TEXT_ADDR ($A000, R7).  16 KiB bank b holds chunks 2b and 2b+1.
TEXT_8K = _kinc("TEXT_8K")
TEXT_CHUNKS = _kinc("TEXT_CHUNKS")
TEXT_ADDR = _kinc("TEXT_ADDR")
CHUNK_SIZE = 0x2000
if TEXT_8K % 2 or TEXT_CHUNKS % 2:
    raise SystemExit("kanji.inc: the text chunks must fill whole 16 KiB banks")
TEXT_BANKS = list(range(TEXT_8K // 2, (TEXT_8K + TEXT_CHUNKS) // 2))


def far_stub_addr() -> int:
    path = OUT / "far_stub.txt"
    if not path.exists():
        raise SystemExit("missing far_stub.txt; assemble the fixed hooks first")
    return int(path.read_text(encoding="utf-8").strip(), 16)


def name_table_entry(idx: int) -> bytes:
    b12 = textdata.bank_bytes(12)
    p = b12[0x2800 + idx] | (b12[0x2900 + idx] << 8)
    if not (0x8000 <= p < 0xC000):
        return b""
    off = p - 0x8000 + 0x14
    end = b12.find(b"\xff", off)
    return b"" if end < 0 else b12[off:end]


# U+3005 (iteration mark) is a 16x16 glyph too (revision 15).
KANJI_RE = re.compile(r"[\u3005\u3400-\u9fff\uf900-\ufaff]")
LINE_CTRL = {"<NL>", "<NLNI>", "<PAGENI>", "<PAGE>", "<END>", "<END_NOWAIT>"}


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
    data_bank: int = 0      # the text chunk (8 KiB bank)
    data_addr: int = 0
    tokens: list[str] = field(default_factory=list)   # as compiled (fit_tokens)
    win: bool = False       # a victory message (WIN_LABELS: the stub's flag)


@dataclass
class Page:
    kanji_order: list[int] = field(default_factory=list)   # first appearance
    names: int = 0          # runtime names ($F3 the item, $F4-$F7, the tactic pick)


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
    if key.startswith("NAME:"):
        # $F2 id: officer id's name, the same whoever is in the party (the
        # original's handler $D2F3 skips put_officer_name's party lookup):
        # its kanji name's width (map mode puts it in kanji).
        name = officer_names().get(int(key[5:], 16))
        if name:
            return sum(2 if KANJI_RE.match(c) else 1 for c in name)
    if key.startswith("NAME") or key.startswith("CALL:"):
        # Runtime names are 2-4 kana; CALL helpers print short names/numbers.
        return 8
    if key.startswith("JUMP:"):
        return 0
    return 1


def reflow(tokens: list[str]) -> list[str]:
    """Insert <NLNI> before visible text would exceed 18 cells."""
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
            out.append("<NLNI>")
            width = 0
            line_has = False
        out.append(tok)
        if w:
            width += w
            line_has = True
    return out


PAGE_BREAKS = ("<PAGE>", "<PAGENI>")      # a new window; <PAGE> indents the next line


def split_pages(tokens: list[str]) -> list[list[str]]:
    pages: list[list[str]] = [[]]
    for tok in tokens:
        if tok in PAGE_BREAKS:
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
            if key.startswith("WORD:") or key.startswith("PLACE:"):
                # $EF is the kanji store's bank 3 and $F0 the kanji controls
                # since 2026-11-13 (the compiled text had none of these).
                raise ValueError(f"<{key}>: the word / place insertions $F0 / $EF are kanji codes now")
            elif key.startswith("ITEM:"):
                out += bytes((0xF1, int(key[5:], 16)))
            elif key.startswith("NAME:"):
                out += bytes((0xF2, int(key[5:], 16)))
            elif key.startswith("CALL:") and int(key[5:], 16) in KANJI_CALLS:
                # Kanji pick: $F0 $FF id lenA, variant A, $F0 $FE lenB,
                # variant B (kanji_msg.asm kanji_ctl).
                oid, name_a, name_b = KANJI_CALLS[int(key[5:], 16)]
                vb = compile_tokens(list(name_b), cmap)
                va = compile_tokens(list(name_a), cmap) + bytes((KCTL, 0xFE, len(vb)))
                out += bytes((KCTL, 0xFF, oid, len(va))) + va + vb
            elif key.startswith("CALL:") and int(key[5:], 16) in KANJI_TROOP_CALLS:
                # Troop pick: <CALL:name helper>, $F0 $FD lenA, variant A,
                # $F0 $FE lenB, variant B (kanji_msg.asm kanji_ctl).
                helper, text_a, text_b = KANJI_TROOP_CALLS[int(key[5:], 16)]
                vb = compile_tokens(list(text_b), cmap)
                va = compile_tokens(list(text_a), cmap) + bytes((KCTL, 0xFE, len(vb)))
                # The name helper $D49A is put_officer_name_target, which
                # the control $F4 runs too: $F4 goes through the message engine,
                # which puts the name in kanji in the battle's pool.
                call = bytes((0xF4,)) if helper == 0xD49A else bytes((0xF8, helper & 0xFF, helper >> 8))
                out += call + bytes((KCTL, 0xFD, len(va))) + va + vb
            elif key.startswith("CALL:") and int(key[5:], 16) in KANJI_SUFFIX_CALLS:
                # Kanji tail: the call, $F0 $FC cells (back over the kana
                # tail), the kanji (kanji_msg.asm kanji_ctl).
                ptr = int(key[5:], 16)
                cells, text = KANJI_SUFFIX_CALLS[ptr]
                tail = bytes((0xF8, ptr & 0xFF, ptr >> 8, KCTL, 0xFC, cells))
                tail += compile_tokens(list(text), cmap)
                if ptr == 0xD565:
                    # The tactic's name: $F0 $FB lenA, variant A (の計, after
                    # the name's kanji from the pool), $F0 $FE lenB, variant
                    # B (the call and its kanji tail; kanji_msg.asm
                    # kanji_ctl).  The name takes a page's reserved entries.
                    va = compile_tokens(list("の" + text), cmap) + bytes((KCTL, 0xFE, len(tail)))
                    out += bytes((KCTL, 0xFB, len(va))) + va + tail
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
            # A kanji: $EC + its store bank (0-3), its pos (kanji.inc STORE_*).
            code = cmap[ch]
            if not 0 <= code < 0x400:
                raise ValueError(f"kanji {ch}: code {code} outside the store")
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


def page_from_bytes(data: bytes) -> list[Page]:
    """Split one compiled message into pages (at <PAGE> / <PAGENI>; the last
    page too, even empty) with each page's kanji in first-appearance order
    and its runtime names: what the message engine's page table holds
    (kanji_msg.asm scan_table: both variants of a pick count)."""
    pages = [Page()]
    i = 0
    while i < len(data):
        b = data[i]
        page = pages[-1]
        if b == KCTL and i + 1 < len(data) and data[i + 1] >= 0xFB:
            # Kanji-pick control: both variants' kanji stay in the page.
            # $FB, the tactic's name, takes reserved entries like a name.
            if data[i + 1] == 0xFB:
                page.names += 1
            i += 4 if data[i + 1] == 0xFF else 3
            continue
        if 0xEC <= b <= 0xEF:
            if i + 1 >= len(data):
                break
            code = ((b - 0xEC) << 8) | data[i + 1]
            if code not in page.kanji_order:
                page.kanji_order.append(code)
            i += 2
            continue
        if b in (0xF1, 0xF2):
            i += 2
            continue
        if 0xF3 <= b <= 0xF7:          # (the item's $F3 too, kanji_msg.asm KITEM;
            page.names += 1            # a 4-kanji item counts two at run time)
        if b in (0xF8, 0xF9):
            i += 3
            continue
        if b in (0xFC, 0xFD):           # <PAGE>, <PAGENI>: the next page
            pages.append(Page())
        i += 1
    return pages


def split_failing_page(tokens: list[str], page_index: int) -> list[str]:
    """Insert a page break inside the failing page.

    Prefer an existing line boundary so the original line layout is kept: an
    <NL> becomes a <PAGE> and an <NLNI> a <PAGENI>, so the next line keeps
    its indent (or none).  If the page has no line boundary (for example a
    short name-heavy page), split at the token boundary closest to half of
    the page's kanji count and force a new line before the page break.
    """
    # Locate the token range for this page.
    bounds = [0]
    for i, tok in enumerate(tokens):
        if tok in PAGE_BREAKS:
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
        if tok in ("<NL>", "<NLNI>"):
            candidates.append((i, k))
    total = k
    if candidates:
        target = total // 2
        best = min(candidates, key=lambda x: abs(x[1] - target))
        out = list(tokens)
        out[best[0]] = "<PAGE>" if out[best[0]] == "<NL>" else "<PAGENI>"
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
    FALLBACK_SPLITS.append(tokens)
    return tokens[:i] + ["<NLNI>", "<PAGE>"] + tokens[i:]


WIDTH_ISSUES: list[str] = []
SPLIT_COUNT = [0]
FALLBACK_SPLITS: list[list[str]] = []    # pages split inside a line (none expected)


def line_width_issues(rec: "Record", data: bytes) -> list[str]:
    """Lines wider than the window: 18 cells, 17 after an indenting break
    ($FA <NL>, $FC <PAGE>).  Runtime names count 8 cells, a fixed name
    ($F2 id) its kanji name's width (as token_width)."""
    issues = []
    width, cap, line = 0, 18, 0
    i = 0
    while i < len(data):
        b = data[i]
        if b == KCTL and i + 2 < len(data) and data[i + 1] >= 0xFB:
            # Pick: count variant A only ($F0 $FE n then skips variant B);
            # $F0 $FC n steps back n cells; $FB's name counts 5 (with its
            # の計, the 8 of a runtime name).
            if data[i + 1] == 0xFC:
                width -= data[i + 2]
            if data[i + 1] == 0xFB:
                width += 5
            i += {0xFF: 4, 0xFD: 3, 0xFC: 3, 0xFB: 3}.get(data[i + 1], 3 + data[i + 2])
            continue
        if 0xEC <= b <= 0xEF:
            width += 2
            i += 2
            continue
        if b in (0xF1, 0xF2):
            width += (token_width(f"<NAME:{data[i + 1]:02X}>") if b == 0xF2 and i + 1 < len(data)
                      else 8)
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


def fit_tokens(rec: "Record", tokens: list[str], cmap: dict[str, int]):
    """Compile tokens, splitting a page with more kanji than the message
    engine's page table holds (MAX_PAGE_ENTRIES) until every page fits.
    Returns (data, pages, tokens): the tokens as compiled
    (tools/scroll_scan.py walks them)."""
    for _ in range(60):
        data = compile_tokens(tokens, cmap)
        if not data:
            # An empty message record must still be a valid END stream;
            # a zero-length data area would make its stub point at the
            # next record.
            data = bytes((0xFF,))
        pages = page_from_bytes(data)
        failed = next((i for i, page in enumerate(pages)
                       if len(page.kanji_order) > MAX_PAGE_ENTRIES), None)
        if failed is None:
            return data, pages, tokens
        tokens = split_failing_page(tokens, min(failed, len(split_pages(tokens)) - 1))
        SPLIT_COUNT[0] += 1
    raise RuntimeError(f"{rec.labels[:1]}: could not fit after 60 splits")


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

    for rec in records:
        # No metadata (2026-11-14): the message engine scans a page's kanji
        # and names at run time; fit_tokens keeps every page in its table.
        tokens = reflow(tokenize(rec.text))
        rec.data, rec.pages, rec.tokens = fit_tokens(rec, tokens, cmap)
        WIDTH_ISSUES.extend(line_width_issues(rec, rec.data))
        rec.win = bool(set(rec.labels) & WIN_LABELS)

    # Deduplicate identical message streams (and victory flags).
    canon: dict[tuple[bytes, bool], Record] = {}
    for rec in records:
        key = (rec.data, rec.win)
        if key not in canon:
            canon[key] = rec
    unique = list(canon.values())

    # Pack every unique message into a chunk, first fit by decreasing size
    # (the order of the dtx among equal sizes).  A message that is only a
    # JUMP keeps its bytes in its stub bank (below) and takes none here.
    chunks = [bytearray() for _ in range(TEXT_CHUNKS)]
    placed = [rec for rec in unique if not (rec.data and rec.data[0] == 0xF9)]
    for rec in sorted(placed, key=lambda r: -len(r.data)):
        for k, chunk in enumerate(chunks):
            if len(chunk) + len(rec.data) <= CHUNK_SIZE:
                rec.data_bank = TEXT_8K + k
                rec.data_addr = TEXT_ADDR + len(chunk)
                chunk += rec.data
                break
        else:
            total = sum(len(r.data) for r in placed)
            raise SystemExit(f"text does not fit {TEXT_CHUNKS} chunks of 8 KiB: "
                             f"{total} bytes, {len(rec.data)} left over "
                             f"(kanji.inc TEXT_CHUNKS)")
    for rec in unique:
        if rec not in placed:
            rec.data_bank = 0
            rec.data_addr = 0

    for rec in records:
        c = canon[(rec.data, rec.win)]
        rec.data_bank = c.data_bank
        rec.data_addr = c.data_addr
    message_map = {}
    for rec in records:
        for label in rec.labels:
            message_map[label] = [rec.data_bank, rec.data_addr] if rec.data_bank else None
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
        stub_addr: dict[tuple[bytes, bool], int] = {}
        used: list[Record] = []
        seen: set[tuple[bytes, bool]] = set()
        for i in range(count):
            rec = index_rec.get((bank, i))
            if rec is None:
                raise SystemExit(f"bank {bank}: missing index {i}")
            key = (rec.data, rec.win)
            if key not in seen:
                seen.add(key)
                used.append(rec)
        for rec in used:
            key = (rec.data, rec.win)
            stub_addr[key] = 0x8000 + start + len(data_area)
            if rec.data and rec.data[0] == 0xF9:
                # A message that is only a JUMP (event code in bank 13/14):
                # its original three bytes here, no far stub.  The engine
                # tests $F9 only at a line's start ($D160); behind a stub the
                # message engine resumes inside the line ($D250), and the
                # jump's bytes printed as text (b11_msg_105, 2026-11-13).
                data_area += rec.data[:3]
                continue
            if rec.data_bank > 0x3F:
                raise SystemExit(f"{rec.labels[:1]}: chunk {rec.data_bank} needs bit 7")
            data_area += bytes((0xF8, far_stub & 0xFF, far_stub >> 8,
                                rec.data_bank | (STUB_WIN if rec.win else 0),
                                rec.data_addr & 0xFF, rec.data_addr >> 8))
        if start + len(data_area) > 0x4000:
            raise SystemExit(f"bank {bank}: stubs overflow: {start + len(data_area):X}")

        orig = original[bank * 0x4000:(bank + 1) * 0x4000]
        out = bytearray(orig)
        lo = bytearray()
        hi = bytearray()
        for i in range(count):
            rec = index_rec.get((bank, i))
            a = stub_addr[(rec.data, rec.win)]
            lo.append(a & 0xFF)
            hi.append(a >> 8)
        out[info["lo"]:info["lo"] + count] = lo
        out[info["hi"]:info["hi"] + count] = hi
        out[start:start + len(data_area)] = data_area
        # The original message text behind the stubs, up to its end (tail):
        # the pointer tables reach only the stubs, so nothing reads it
        # (0 bytes in Mesen's CDL on five paths).  Free
        # since the debloat (2026-11-14).
        out[start + len(data_area):info["tail"]] = bytes(info["tail"] - start - len(data_area))
        toff = TRAMPOLINE_ADDR - 0x8000
        out[toff:toff + len(trampoline)] = trampoline
        (OUT / f"bank{bank:02d}.bin").write_bytes(bytes(out))
        print(f"bank {bank}: {len(used)} stubs, {len(data_area)} bytes "
              f"at ${start:04X}")

    for b in TEXT_BANKS:
        image = bytearray(0x4000)
        for half in (0, 1):
            k = 2 * b + half - TEXT_8K
            image[half * CHUNK_SIZE:half * CHUNK_SIZE + len(chunks[k])] = chunks[k]
        (OUT / f"bank{b:02d}.bin").write_bytes(bytes(image))

    # Report
    pages = [page for rec in unique for page in rec.pages]
    report = {
        "inventory": len(cmap),
        "messages": len(unique),
        "pages": len(pages),
        "max_page_kanji": max((len(p.kanji_order) for p in pages), default=0),
        "max_page_names": max((p.names for p in pages), default=0),
        "text_bytes": sum(len(rec.data) for rec in placed),
        "text_chunks": {TEXT_8K + k: len(chunk) for k, chunk in enumerate(chunks)},
        "data_banks": TEXT_BANKS,
        "width_issues": len(WIDTH_ISSUES),
        "split_pages": SPLIT_COUNT[0],
        "fallback_splits": len(FALLBACK_SPLITS),
    }
    (OUT / "kanji_width_issues.txt").write_text(chr(10).join(WIDTH_ISSUES) + chr(10), encoding="utf-8")
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
