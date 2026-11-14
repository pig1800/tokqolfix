#!/usr/bin/env python3
"""The title screen and the attract mode in kanji (titlekanji.txt, the
user's spec, 2026-11-14): data for tools/asm/attract.asm (bank ATT_BANK).

Each screen has its own BG tile set, uploaded while the screen is black:
kanji first from tile $00 (4 tiles each, 8x16 order TL, BL, TR, BR, from
the kanji store), then every 8x8 glyph the screen needs (the game's font,
bank 9, and the title's letters, bank 2), and tile $FF blank (the
nametables are filled with it).  The title screen keeps the logo at
$80-$DF; the intro over it uses the title's set.  The portraits are 8x16
sprites (the user's choice, 2026-11-14), their tiles from the original
portrait parts (banks 2/3).

Writes decomp/build/kanji/attract_lo.inc (tile sets, portraits; read while
a kanji store bank is at R7, so attract.asm keeps them below $A000) and
attract_hi.inc (the strings, draw_string format).
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import attract_text as AT          # noqa: E402
import kanji_common as kc          # noqa: E402
import textdata                    # noqa: E402

ROM = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
OUT = ROOT / "decomp" / "build" / "kanji"

BLANK = 0xFF                       # the blank tile (every set writes it blank)
DAK, HANDAK = 0x72, 0x73           # the font's ゛ ゜ (drawn on the row above)
LOGO = range(0x80, 0xE0)           # the title logo's tiles
LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ©®"   # the title's letter tiles $E0-$FB

# Sources the game reads (pointers checked against the ROM below).
FONT_PTR = (15, 0xDE9B, 9, 0xBA00)     # load_battle_palette: bank 9, 1bpp, 128 tiles
LETTER_PTR = (13, 0x8833, 2, 0xBE00)   # the title's letter copy: bank 2, 1bpp, $E0-$FF
TITLE_PTR = (13, 0x8840)               # the title's draw_string block (bank 13)
PHRASES = (7, 0x9570)                  # bank 7's phrase pointer table
PORTRAIT_IDS = (7, 0x975B)             # bank 7's portrait list (text_load_page ids)
PHRASE_COUNTS = (7, 0x9756)            # phrases per portrait screen

INTRO_ROW, INTRO_COL = 13, 5
BAND_ROWS = (5, 13, 21)                # each band's first line (kana row)
BAND_COLS = (9, 2, 9)
FINAL_ROW, FINAL_COL = 7, 4
BAND_TOP = (32, 96, 160)               # portrait tops (pixels; tile rows 4, 12, 20)


def prg() -> bytes:
    return ROM.read_bytes()[16:]


PRG = b""


def rd(bank: int, addr: int) -> int:
    return PRG[bank * 0x4000 + (addr & 0x3FFF)]


def rdw(bank: int, addr: int) -> int:
    return rd(bank, addr) | rd(bank, addr + 1) << 8


def records(bank: int, addr: int) -> tuple[list[tuple[int, int, bytes]], int]:
    """A draw_string block: (PPU address, length byte, data) records; the
    data of a fill record is its one byte.  Returns the records and the
    address of the $FF that ends them."""
    out = []
    while rd(bank, addr) != 0xFF:
        ppu = rd(bank, addr) << 8 | rd(bank, addr + 1)
        ln = rd(bank, addr + 2)
        n = ln & 0x3F
        if ln & 0x40:
            out.append((ppu, ln, bytes((rd(bank, addr + 3),))))
            addr += 4
        else:
            out.append((ppu, ln, bytes(rd(bank, addr + 3 + i) for i in range(n))))
            addr += 3 + n
    return out, addr


def is_attr(ppu: int) -> bool:
    return (ppu & 0x3FF) >= 0x3C0


# ----------------------------------------------------------------------
# Glyphs.  A cell is None (blank), ("K", code, part) part 0-3 = TL, BL,
# TR, BR, ("F", font tile) or ("L", letter index).
# ----------------------------------------------------------------------
NORMAL = {"!": "！", "/": "／", "-": "－"}


def glyph8(ch: str) -> tuple[tuple, int | None]:
    """An 8x8 glyph and its mark (DAK / HANDAK / None)."""
    if ch in LETTERS:
        return ("L", LETTERS.index(ch)), None
    ch = NORMAL.get(ch, ch)
    code = textdata.CHAR_TO_BYTE.get(ch)
    if code is None:
        raise SystemExit(f"attract: no 8x8 glyph for {ch!r}")
    if code < 0x80:
        return ("F", code), None
    base = code & 0x7F
    if base >= 0x62:
        return ("F", base - 0x0A), HANDAK
    return ("F", base), DAK


CODES: dict[str, int] = {}


def layout(text: str) -> tuple[list, list]:
    """The line's two rows of cells (top: kanji tops and marks; bottom:
    kanji bottoms and the 8x8 glyphs)."""
    top, bot = [], []
    for ch in text:
        if ch in "　 ":
            top.append(None)
            bot.append(None)
        elif kc.KANJI_RE.fullmatch(ch):
            if ch not in CODES:
                raise SystemExit(f"attract: {ch} is not in the kanji store")
            c = CODES[ch]
            top += [("K", c, 0), ("K", c, 2)]
            bot += [("K", c, 1), ("K", c, 3)]
        else:
            g, mark = glyph8(ch)
            top.append(("F", mark) if mark else None)
            bot.append(g)
    return top, bot


class TileSet:
    def __init__(self, name: str, reserved: range | None = None):
        self.name = name
        self.reserved = reserved
        self.kanji: list[int] = []
        self.small: list[tuple] = []
        self.tile: dict = {}

    def add(self, cells: list) -> None:
        for cell in cells:
            if cell is None:
                continue
            if cell[0] == "K":
                if cell[1] not in self.kanji:
                    self.kanji.append(cell[1])
            elif cell not in self.small:
                self.small.append(cell)

    def assign(self) -> None:
        for i, code in enumerate(self.kanji):
            for part in range(4):
                self.tile[("K", code, part)] = 4 * i + part
        t = 4 * len(self.kanji)
        for cell in self.small:
            while self.reserved and t in self.reserved:
                t += 1
            if t >= BLANK:
                raise SystemExit(f"attract set {self.name}: {len(self.kanji)} kanji and "
                                 f"{len(self.small)} 8x8 glyphs do not fit below ${BLANK:02X}")
            self.tile[cell] = t
            t += 1
        self.end = t

    def tiles(self, cells: list) -> list[int | None]:
        return [None if c is None else self.tile[c] for c in cells]

    def free(self) -> int:
        used = self.end - (len(self.reserved) if self.reserved and self.end > self.reserved.start else 0)
        cap = BLANK - (len(self.reserved) if self.reserved else 0)
        return cap - used


def row_record(row: int, col: int, cells: list[int | None]) -> bytes:
    """One nametable row as a draw_string record, blanks at the ends
    trimmed, inner blanks as BLANK."""
    idx = [i for i, c in enumerate(cells) if c is not None]
    if not idx:
        return b""
    a, b = idx[0], idx[-1]
    data = bytes(BLANK if c is None else c for c in cells[a:b + 1])
    if col + b > 31:
        raise SystemExit(f"attract: a line at row {row} ends past column 31")
    ppu = 0x2000 + 32 * row + col + a
    return bytes((ppu >> 8, ppu & 0xFF, len(data))) + data


def fill_record(ppu: int, n: int, value: int) -> bytes:
    return bytes((ppu >> 8, ppu & 0xFF, 0x40 | n, value))


def rec_bytes(rec: tuple[int, int, bytes]) -> bytes:
    ppu, ln, data = rec
    return bytes((ppu >> 8, ppu & 0xFF, ln)) + data


def db(data: bytes, per: int = 16) -> list[str]:
    return [".db " + ",".join(f"${b:02X}" for b in data[i:i + per])
            for i in range(0, len(data), per)]


def build() -> dict:
    global PRG
    PRG = prg()
    CODES.clear()
    CODES.update(kc.code_map())

    # The sources the game itself reads.
    for bank, at, src_bank, want in (FONT_PTR, LETTER_PTR):
        if rdw(bank, at) != want:
            raise SystemExit(f"attract: bank {bank} ${at:04X} is not the ${want:04X} pointer")

    # ---------------- the title screen and the intro ----------------
    title_set = TileSet("title", LOGO)
    title_ptr = rdw(*TITLE_PTR)
    title_recs, _ = records(13, title_ptr)
    # The original's records, its tiles as cells (the copyright line is
    # replaced by the kanji line, same row and columns).
    def cells_of(data: bytes) -> list:
        out = []
        for b in data:
            if b == 0x0A:
                out.append(None)
            elif b in LOGO:
                out.append(("LOGO", b))
            elif b >= 0xE0:
                out.append(("L", b - 0xE0))
            else:
                out.append(("F", b))
        return out
    title_rows = []          # (row, col, cells)
    attr_tail = None
    off = 0
    copyright_at = None
    for ppu, ln, data in title_recs:
        if is_attr(ppu):
            if attr_tail is None:
                attr_tail = title_ptr + off
        else:
            if attr_tail is not None:
                raise SystemExit("attract: the title block has tiles after its attributes")
            if ln & 0xC0:
                raise SystemExit(f"attract: title record ${ppu:04X} is a fill or vertical")
            row, col = (ppu - 0x2000) // 32, (ppu - 0x2000) % 32
            if ppu == 0x22E8:
                copyright_at = (row, col, len(data))
            else:
                title_rows.append((row, col, cells_of(data)))
        off += 3 + (1 if ln & 0x40 else ln & 0x3F)
    if copyright_at is None or attr_tail is None:
        raise SystemExit("attract: the title block changed (no copyright line / attributes)")
    crow, ccol, cn = copyright_at
    ctop, cbot = layout(AT.TITLE_COPYRIGHT)
    if len(cbot) > cn:
        raise SystemExit(f"attract: the copyright line is {len(cbot)} columns, the original {cn}")
    for _, _, cells in title_rows:
        title_set.add([c for c in cells if c and c[0] != "LOGO"])
    title_set.add(ctop + cbot)
    intro = [layout(t) for t in AT.INTRO]
    for top, bot in intro:
        title_set.add(top + bot)
    title_set.assign()

    def tile_of(ts: TileSet, cells: list) -> list[int | None]:
        return [None if c is None else (c[1] if c[0] == "LOGO" else ts.tile[c]) for c in cells]

    title_nt = b""
    for row, col, cells in title_rows:
        title_nt += row_record(row, col, tile_of(title_set, cells))
    title_nt += row_record(crow - 1, ccol, title_set.tiles(ctop))
    title_nt += row_record(crow, ccol, title_set.tiles(cbot))
    title_nt += b"\xFF"

    # The intro's first draw erases the title's text lines (not the logo
    # or TM): the PUSH START row, the copyright line's two rows, the
    # ®©CAPCOM row (bank 7's own erase block did the kana rows).
    intro_clr = b""
    for row, col, cells in title_rows:
        if row >= 11:
            intro_clr += fill_record(0x2000 + 32 * row + col, len(cells), BLANK)
    intro_clr += fill_record(0x2000 + 32 * (crow - 1) + ccol, cn, BLANK)
    intro_clr += fill_record(0x2000 + 32 * crow + ccol, cn, BLANK)
    intro_clr += b"\xFF"

    # ---------------- the original phrases (attribute records) ----------------
    nphr = [rd(PHRASE_COUNTS[0], PHRASE_COUNTS[1] + i) for i in range(5)]
    counts = [len(AT.INTRO)] + nphr + [len(AT.FINAL)]
    total = sum(counts)
    phrase_attr: list[bytes] = []
    phrase_rows: list[set[int]] = []
    for k in range(total):
        recs, _ = records(7, rdw(PHRASES[0], PHRASES[1] + 2 * k))
        phrase_attr.append(b"".join(rec_bytes(r) for r in recs if is_attr(r[0])))
        phrase_rows.append({(r[0] - 0x2000) // 32 for r in recs if not is_attr(r[0])})

    # ---------------- the lines of every screen ----------------
    screens = []          # per set after the title: (name, lines [(row, col, top, bot)])
    lines_title = [(INTRO_ROW + 2 * i, INTRO_COL, top, bot) for i, (top, bot) in enumerate(intro)]
    for n, bands in enumerate(AT.PORTRAITS):
        if len(bands) * 3 != nphr[n]:
            raise SystemExit(f"attract: portrait screen {n + 1} has {len(bands)} bands, "
                             f"the original {nphr[n]} phrases")
        lines = []
        for b, band in enumerate(bands):
            for i, text in enumerate(band):
                top, bot = layout(text)
                col = BAND_COLS[b]
                if b == 1 and col + len(bot) > 24:
                    raise SystemExit(f"attract: screen {n + 1} band 2 line {text} runs into the portrait")
                lines.append((BAND_ROWS[b] + 2 * i, col, top, bot))
        screens.append((f"portrait{n + 1}", lines))
    lines = []
    for i, text in enumerate(AT.FINAL):
        top, bot = layout(text)
        lines.append((FINAL_ROW + 2 * i, FINAL_COL, top, bot))
    screens.append(("final", lines))

    sets = [title_set]
    all_lines = list(lines_title)
    for name, lines in screens:
        ts = TileSet(name)
        for _, _, top, bot in lines:
            ts.add(top + bot)
        ts.assign()
        sets.append(ts)
        all_lines += lines
    owner = [0] * len(AT.INTRO)
    for s, (_, lines) in enumerate(screens):
        owner += [s + 1] * len(lines)
    assert len(all_lines) == total

    # The fade: a line is drawn while BG palette 2 is black and fades in
    # through it, so its cells must be palette 2 then, and every line drawn
    # before on the screen must not be (it would go black).  The attribute
    # state is followed from the screen's start (the title's attributes
    # for the intro, $AA for the others); a line the original's records
    # leave in palette 1 gets a record for its own quadrants (the intro's
    # last line, row 25: the original's oversight, the user's fix of
    # 2026-11-14).
    def apply(attr: bytearray, recs: bytes) -> None:
        i = 0
        while recs[i] != 0xFF:
            ppu, ln = recs[i] << 8 | recs[i + 1], recs[i + 2]
            n = ln & 0x3F
            data = bytes((recs[i + 3],)) * n if ln & 0x40 else recs[i + 3:i + 3 + n]
            for j, v in enumerate(data):
                attr[(ppu & 0x3F) + j] = v
            i += 4 if ln & 0x40 else 3 + n

    def quad(row: int, col: int) -> tuple[int, int]:
        return (row // 4) * 8 + col // 4, ((row % 4) // 2) * 4 + ((col % 4) // 2) * 2

    def pal(attr: bytearray, row: int, col: int) -> int:
        a, sh = quad(row, col)
        return (attr[a] >> sh) & 3

    title_attr = bytearray(64)
    apply(title_attr, b"".join(rec_bytes(r) for r in title_recs if is_attr(r[0])) + b"\xFF")
    phrases = []
    fixed = []
    attr = bytearray(64)
    drawn: list = []
    for k, (row, col, top, bot) in enumerate(all_lines):
        if not phrase_rows[k] <= {row - 1, row}:
            raise SystemExit(f"attract: phrase {k} is on rows {sorted(phrase_rows[k])}, "
                             f"the kanji line on {row - 1}-{row}")
        if k == 0 or owner[k] != owner[k - 1]:
            attr = bytearray(title_attr) if owner[k] == 0 else bytearray([0xAA] * 64)
            drawn = []
        rec = phrase_attr[k]
        apply(attr, rec + b"\xFF")
        cols = range(col, col + len(bot))
        if any(pal(attr, row, c) != 2 for c in cols):
            new_attr = bytearray(attr)
            for c in cols:
                a, sh = quad(row, c)
                new_attr[a] = (new_attr[a] & ~(3 << sh) & 0xFF) | (2 << sh)
            ch = [i for i in range(64) if new_attr[i] != attr[i]]
            a0, a1 = ch[0], ch[-1]
            rec += bytes((0x23, 0xC0 + a0, a1 - a0 + 1)) + bytes(new_attr[a0:a1 + 1])
            attr = new_attr
            fixed.append(k)
        for prow, pcols in drawn:
            if any(pal(attr, prow, c) == 2 for c in pcols):
                raise SystemExit(f"attract: phrase {k} leaves an earlier line (row {prow}) in palette 2")
        drawn.append((row, cols))
        ts = sets[owner[k]]
        data = (rec + row_record(row - 1, col, ts.tiles(top))
                + row_record(row, col, ts.tiles(bot)) + b"\xFF")
        phrases.append(data)

    # ---------------- portraits ----------------
    por = []
    i = 0
    for n in range(5):
        cnt = len(AT.PORTRAITS[n])
        ids = [rd(PORTRAIT_IDS[0], PORTRAIT_IDS[1] + i + j) for j in range(cnt)]
        i += cnt
        parts = []
        for pid in ids:
            ptr = rd(12, 0xA800 + pid) | rd(12, 0xA900 + pid) << 8
            for r in range(6):
                pb = rd(12, ptr + 10 + r)
                src = 0x8800 + (pb & 0x7F) * 0x60
                parts.append(bytes((3 if pb & 0x80 else 2, src & 0xFF, src >> 8)))
        por.append((cnt, b"".join(parts)))

    # ---------------- output ----------------
    lo = ["; generated by tools/attract_build.py (titlekanji.txt): do not edit",
          f"ATT_NSETS = {len(sets)}",
          f"ATT_NINTRO = {len(AT.INTRO)}",
          f"ATT_NFINAL = {len(AT.FINAL)}"]
    lo.append(".db " + ",".join(f"<att_set{s}" for s in range(len(sets))))
    lo.insert(4, "att_set_lo:")
    lo.append("att_set_hi:")
    lo.append(".db " + ",".join(f">att_set{s}" for s in range(len(sets))))
    for s, ts in enumerate(sets):
        lo.append(f"att_set{s}:                  ; {ts.name}: {len(ts.kanji)} kanji, "
                  f"{len(ts.small)} 8x8, tiles $00-${ts.end - 1:02X}")
        body = bytes([len(ts.kanji)])
        for code in ts.kanji:
            body += bytes((code >> 8, code & 0xFF))
        body += bytes([len(ts.small)])
        for cell in ts.small:
            src = cell[1] if cell[0] == "F" else 0x80 | cell[1]
            body += bytes((ts.tile[cell], src))
        lo += db(body)
    lo.append("att_por_n:")
    lo += db(bytes(c for c, _ in por))
    lo.append("att_por_lo:")
    lo.append(".db " + ",".join(f"<att_por{n}" for n in range(5)))
    lo.append("att_por_hi:")
    lo.append(".db " + ",".join(f">att_por{n}" for n in range(5)))
    for n, (cnt, data) in enumerate(por):
        lo.append(f"att_por{n}:                  ; {cnt} portraits x 6 parts: bank, source")
        lo += db(data, 18)
    lo.append("att_nphr:")
    lo += db(bytes(nphr))
    lo.append("att_bands:")
    lo += db(bytes(BAND_TOP))

    hi = ["; generated by tools/attract_build.py (titlekanji.txt): do not edit",
          f"ATT_TITLE_ATTR = ${attr_tail:04X}      ; the title block's attribute records (bank 13)",
          "att_title_nt:"]
    hi += db(title_nt)
    hi.append("att_intro_clr:")
    hi += db(intro_clr)
    hi.append("att_phr:")
    hi += [".dw " + ",".join(f"att_ph{k}" for k in range(j, min(j + 8, total)))
           for j in range(0, total, 8)]
    for k, data in enumerate(phrases):
        hi.append(f"att_ph{k}:")
        hi += db(data)

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "attract_lo.inc").write_text("\n".join(lo) + "\n", encoding="utf-8")
    (OUT / "attract_hi.inc").write_text("\n".join(hi) + "\n", encoding="utf-8")
    report = {ts.name: (len(ts.kanji), len(ts.small), ts.end, ts.free()) for ts in sets}
    report["phrase_max"] = max(len(p) for p in phrases)
    report["title_attr"] = attr_tail
    report["fade_fixed"] = fixed
    return report


if __name__ == "__main__":
    r = build()
    for k, v in r.items():
        print(k, v)
