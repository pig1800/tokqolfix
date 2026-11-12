#!/usr/bin/env python3
"""Build the 512 KiB kanji-target resources.

Owns the fixed-bank stubs, the hack banks (code + glyph data), the
trampoline, the font, the text overlay and the generated text banks.
The original 256 KiB target never runs this script.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROM = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
OUT = ROOT / "decomp" / "build" / "kanji"
ASM = ROOT / "tools" / "asm"
ASM6F = ROOT / "tools" / "toolchain" / "asm6f" / "asm6f_64.exe"

TEXT_BANK_START = 18
TEXT_BANK_END = 22
OVERLAY_LIMIT = 0x800
HACK_CODE_LIMIT = 0xC00
GLYPH_BASE = 0x8C00
GLYPHS_PER_BANK = 359
HACK_BANKS = (23, 24)          # grown by build_hack_banks to fit the font

# Fixed-bank regions assigned to the hooks (revision 11; $C460-$C47D, the
# dead MMC1 reset/init, and $F004-$F00B since the MMC3 port, revision 21).
HOOK_RANGES = ((0xC5A6, 0xC6D1), (0xC460, 0xC47D), (0xC489, 0xC49D),
               (0xC4AD, 0xC4B9), (0xC4BA, 0xC4CA), (0xD291, 0xD2B6),
               (0xF004, 0xF039), (0xFFE0, 0xFFEF))

# QoL: copy_pointer_triplet and its divisor table (the decimal digits),
# replaced by a stub to the UI bank (UIF_DEC); the space holds bs_wait and
# blk_main.  Original bytes, by hash; joins HOOK_RANGES.
QOL_REGIONS = (
    (0xD671, 0xD6C1, "039df481b2024e448ac04f8bd2252af2746608ae28741435ac022cbd78aecbf1"),
    # div24_shift, replaced by a stub to the UI bank (UIF_DIV); the space
    # holds blk_fast
    (0xC1D2, 0xC216, "4e77aef7dc99cbeaaabbc1781c494c6a195d16fe951b86e16d7875118c69c1d9"),
)
HOOK_RANGES = HOOK_RANGES + tuple((lo, hi) for lo, hi, _ in QOL_REGIONS)

# Map-canvas step 2 (four-screen nametables): game routines rewritten in
# place by the fixed-bank source (cursor_to_ppu + set_scroll_from_cursor,
# the walking scroll's vertical part, draw_tile_run's column wrap,
# draw_map_object, text_render_cell's row wrap, tile_address, the walking
# tasks' tables, the full-redraw starts).  Original bytes, by hash; the source may only assemble
# inside these ranges (they join HOOK_RANGES).
FOURSCREEN_REGIONS = (
    (0xD7E9, 0xD83D, "1a20e8d1517f631dc22d5b53b063acb4dfe2c433d0e1985519ea16f217a9633d"),
    (0xF3A3, 0xF3CA, "a928dd4f41b3d773dd5920dd700e35c68e84877aca64d92da85eb240d7d530f6"),
    (0xDAB9, 0xDAF1, "6cce9391919f5510e2f58d8ea573235dbecd841c456e5fa934308cde8f62d34c"),
    (0xDAF2, 0xDB7D, "7ffbf00e0d7de955c9ff4ea7ad5bed1497d29b3f6e96f1b4cd12f0b08be32f77"),
    (0xDC0E, 0xDC19, "2c349426dc267b6e6e560da18eafca9d5f2008b10cbf1758c5eda8a0aa598454"),
    # write-ahead rows (the 256-byte attribute shadow at MAP_ATTR): tile_address
    # and its table, the shadow's users at $CAA2 / $F5E7, the walking tasks'
    # tables, the 17-row full redraws
    (0xD953, 0xD97B, "6333b4c2e5c79be00e0e38f789109888a551ba7e864d22064e4e491dd21af516"),
    (0xCAA3, 0xCAA4, "1417a296c21274cec9c3d2c91ca16a5dff7840833de2a46b05c29e5de9900d9f"),
    (0xCAA8, 0xCAA9, "1417a296c21274cec9c3d2c91ca16a5dff7840833de2a46b05c29e5de9900d9f"),
    (0xF5E8, 0xF5E9, "1417a296c21274cec9c3d2c91ca16a5dff7840833de2a46b05c29e5de9900d9f"),
    (0xF5EF, 0xF5F0, "1417a296c21274cec9c3d2c91ca16a5dff7840833de2a46b05c29e5de9900d9f"),
    (0xF697, 0xF697, "beead77994cf573341ec17b58bbf7eb34d2711c993c1d976b128b3188dc1829a"),
    (0xF6A1, 0xF6A4, "02e79c102e8e0f3cba6eeda99a4986ebbc0f1db25a370b4a11d01ab1cb9b6cf9"),
    (0xF6BD, 0xF6C0, "0edb780690f2c0fa78849f05ab91dd5e8497e5c437e5fc4b92c4131c4fc62111"),
    (0xF6C5, 0xF6C8, "f47d636092da9ae44e31d7c4c26ea7bdc91103a436f550bbc71d0b20602f8727"),
    (0xF6D4, 0xF6DB, "d5447f859e320b870d1494e555e597021fe36b1d751d0f380e96e71ff988bfd3"),
    (0xF6DC, 0xF6DF, "cbfd342bd219e33284ed36c42bda65fdc7633dac9c1415ff568c2bbd3b26ca10"),
    (0xCDDF, 0xCDE9, "d815102641b740f24cb15013a14430e151a40ecb2d9b269124de8c65ab99dd1f"),
    (0xD97C, 0xD983, "59d6fbaa0e124fedafa8d71450788ecc66187c4de7c1cb26c187811e297e4619"),
    # map-canvas step 3 (the dialogue canvas): text_init's window rows call
    # the canvas RAM code ("jsr cursor_to_ppu / jsr tile_address", both
    # "jsr scroll_map")
    (0xCA59, 0xCA5E, "3bd9cdb34f6789f854dca9d6e5fcdc4989ad14f7708167bd2464018882606c2b"),
    (0xCB1B, 0xCB1D, "74dd75f2c35246dd03d1cadfc82249f80c94c339b89e416da509441ba48ea980"),
    (0xCB80, 0xCB82, "74dd75f2c35246dd03d1cadfc82249f80c94c339b89e416da509441ba48ea980"),
    # the reset vector's "jmp reset_init": early_reset (MMC3 + hack_init first)
    (0xFFDC, 0xFFDE, "4ef378f055abd7aab3b9e59192722bf57c2c54102b0b6b4feadf944e2718a88e"),
    # the nametable fill set_ppu_scroll: "jmp cv_fill" (the lower twin too)
    (0xC2AB, 0xC2AD, "d6ef7c6f987cda6bf37ed124b7b52c2980e37eb3d0c54d4ce308136289188b49"),
)
HOOK_RANGES = HOOK_RANGES + tuple((lo, hi) for lo, hi, _ in FOURSCREEN_REGIONS)

# load_text_graphics and the palette tables it alone reads ($C5A6-$C6D1).
# The routine is rewritten in place to read the tables from the hack bank;
# the rest of the range holds hook code.  Original bytes, by hash.
PALETTE_REGION = (0xC5A6, 0xC6D2,
                  "5da1189349cd3b7f8bd9ca7c46477a5afb08af1814ac67c97e274da582facafe")
PALETTE_TABLES = (0xC5EF, 0xC6D2)           # data_C5EF .. end of data_C6C2
PALETTE_PTRS = (0xC6B2, 0xC6C2, 16)         # low / high pointer tables
HACK_CODE2 = 0xB900                         # second hack code segment (hack.asm)
PAL_DATA = 0xBF00                           # KANJI_PAL_DATA in kanji.inc

# Map-canvas step 3: the canvas RAM code (canvas_ram.asm, assembled for
# CV_RAM) is stored in PRG bank CV_BANK at $A000; hack_init copies
# CV_RAM_PAGES pages of it at reset.  Its entry labels go to canvas_ram.inc
# for the fixed bank and the hack bank.
CV_BANK = 27
CV_RAM = 0x7900
CV_RAM_PAGES = 7
# Step B (INFO_SCREEN.md): the UI bank (ui.asm) with the info-screen
# renderer, its own copy of the UI kanji glyphs and the item / tactic kanji
# tables (ui_data.inc, generated here).
UI_BANK = 28
UI_RAM = 0x7F9C                 # kanji.inc UI_DECY, UI_DECX, UI_RAM2, UI_RAM: the UI bank's battery-RAM state
REWARD_KANJI = "金兵糧経験値"   # the reward window $22 (ui_battle.asm ui_reward_g)
REWARD_TPL = 0x923C             # its template in bank 14 (bank14.asm b14_k_reward_tpl)
UI_ITEM_TYPES = ("weapon", "armor", "helmet", "consumable", "keyitem")
# The battle command window's 15 fixed kanji in group order 8-22 (step B
# item 7, ui_battle.asm): filled from the back, 道具 last, 残 before them.
UI_FIXED = "総攻撃退却武将戦策略防御残道具"
# Decision 11: every UI glyph of the bank-9 block ($E0-$FE, CPU $BE00) is
# moved to plane 1 in the kanji target's copy.
UI_BLOCK_PLANE1 = range(0xEF, 0xFB)
# Decision 11: the info screen's P2 (palette set 8, also the battle's base)
# shows plane 1 only: 0F 0F 17 17 (the battle's gauge code sets colours 2/3).
PAL_SET8_P2 = bytes((0x0F, 0x0F, 0x17, 0x17))
# The info screen's attribute cells (16x16): (palette, first row, last row,
# first column, last column) in tiles; every other cell is P0.  P1 shows
# plane 1 (the plane-1 kanji, S.P), P2 the bars, P3 the portrait.
INFO_ATTR_CELLS = (
    (3, 4, 9, 0, 7),        # portrait
    (1, 4, 11, 10, 15),     # 武力 知力 攻撃 武装度
    (1, 12, 13, 0, 7),      # the name in kanji (original engine)
    (1, 12, 13, 10, 13),    # S.P
    (2, 4, 13, 20, 31),     # bars
    (1, 14, 17, 2, 7),      # 兵士数 (rows 15-16)
    (1, 14, 15, 20, 25),    # 策略 (the tactic window's title, columns 21-24)
    (1, 16, 27, 18, 21),    # the tactic lines' first two kanji
    (1, 18, 19, 6, 11),     # 装備 (the equipment window's title, columns 7-10)
)

CV_LABELS = ("cv_irq", "cv_sm", "cv_nmi", "cv_w1", "cv_stage",
             "cv_irq_end", "cv_ram_end",
             "cv_stream", "cv_sforce", "cv_sreload", "cv_fill", "cv_wincb",
             "txr_call", "txr_rr",
             "txr_dlx", "txr_rcx", "txr_cur", "txr_mi", "txr_rd", "txr_tpm")
# The map text renderer (TEXT_RENDERER.md): bank 26, its tables in
# battery RAM from TXR_TABLES up (kanji.inc).
TXR_BANK = 26
TXR_TABLES = 0x7BF5

# The reset code's mapper writes and RAM-clear setup ($F004-$F039) are
# rewritten by the fixed-bank source; these are the original bytes.
RESET_REGION = (0xF004, bytes.fromhex(
    "a90e20b7c42068c4"
    "a9008dd9bf4a8dd9bf4a8dd9bf4a8dd9bf4a8dd9bf"
    "a9008dffdf4a8dffdf4a8dffdf4a8dffdf4a8dffdf"
    "a900a2f0"))

# Patch sites and the original bytes they replace.  Any mismatch means
# the baseline changed and the patch needs re-auditing.
PATCH_SITES = {
    0xC486: bytes((0xA9, 0x01, 0x85)),       # set_bank_lock: lda #1 / sta lock
    0xC4AA: bytes((0x48, 0xA5, 0xEB)),       # restore_bank_after_nmi: pha / lda lock
    0xC343: bytes((0xAD, 0x02, 0x20)),       # loc_C343 lda PPUSTATUS
    0xD28E: bytes((0xB0, 0x27, 0xC9)),       # bcs / cmp #$EF
    0xD2C7: bytes((0x9D, 0x00, 0x03)),       # sta $0300,x
    0xEF0B: bytes((0xA9, 0x08, 0x20, 0xAA, 0xC4)),  # lda #8 / jsr restore_bank_after_nmi
    0xEF31: bytes((0x68, 0xA8, 0x68)),       # NMI epilogue start (pla/tay/pla)
    0xD1C8: bytes((0x20, 0x56, 0xD4)),       # <PAGE> wait: jsr text_draw_char
    0xFFFE: bytes((0x79, 0xEE)),             # IRQ vector: the NMI handler
    0xDBED: bytes((0x7C, 0xDC)),             # text_render_cell: jmp loc_DC7C
    0xD416: bytes.fromhex("a5f4c907d004a90ad007bd19031002a90a"),  # text_redraw_lines cell copy
    # battle window templates $11, $12, $16, $17 (the patched lengths)
    0xEA9C: bytes.fromhex("02fd0ffa1a1a103f0a0a193f143f9311fa15123239120a1a"),
    0xEAC8: bytes.fromhex("02fd08fa1a1a103ffa1512323912fae13f913bfa9e3f92ff"),
    0xEB23: bytes.fromhex("02fd14faf89186f89186faf89186f89186faf89186f89186"),
    0xEB43: bytes.fromhex("02fd146d0c0c0c2314320af6f70a0a0a0a0c0c0c0c0c6efaf88a96f823b7f823b7faf823b7f823b7faf8"),
    # window $22's template pointer (data_EDA1 / data_EDD1 + $22): $EC34
    0xEDC3: bytes((0x34,)),
    0xEDF3: bytes((0xEC,)),
    # battle setup: jsr wait_vblank_queued (the enemy roll, the name
    # loop's three sites), the loop's end
    0xDF32: bytes((0x20, 0xA7, 0xC0)),
    0xE0A3: bytes((0x20, 0xA7, 0xC0)),
    0xE200: bytes((0x20, 0xA7, 0xC0)),
    0xE238: bytes((0x20, 0xA7, 0xC0)),
    0xE10F: bytes.fromhex("e00af0034ca3e0"),   # cpx #$0A / beq intro / jmp loc_E0A3
    # the map text renderer (TEXT_RENDERER.md)
    0xDD03: bytes.fromhex("a9009d"),           # text_draw_line: lda #0 / sta $0400,x
    0xDBCA: bytes.fromhex("a656bd"),           # text_render_cell: ldx text_line / lda
    0xCD07: bytes.fromhex("689d0004"),         # text_draw_cursor: pla / sta $0400,x
    0xCF22: bytes.fromhex("208dde"),           # screen_refresh: jsr load_battle_palette
    # the map UI in kanji (TEXT_RENDERER.md "Kanji UI")
    0xCC02: bytes.fromhex("2040d3"),           # text_input: jsr text_put_tile
    0xD5C0: bytes.fromhex("2040d3"),           # draw_string_from_pointer: jsr text_put_tile
    0xEB74: bytes((0x02, 0x0A)),               # window $18 (gold, food): column +2, width 10
    0xEBCF: bytes((0x03, 0x08)),               # window $1C (buy / sell): column +3, width 8
    # return_inline_block: tsx / pla / pla / lda $0101,x / sta $F3 /
    # lda $0102,x / sta $F4 (it reads its return address after popping it)
    0xC4FD: bytes.fromhex("ba6868bd010185f3bd020185f4"),
}
BSETUP_WAITS = (0xDF32, 0xE0A3, 0xE200, 0xE238)   # -> jsr bs_wait


def prg() -> bytes:
    return ROM.read_bytes()[16:]


def write_bank(name: str, data: bytes) -> None:
    assert len(data) == 0x4000, (name, len(data))
    (OUT / name).write_bytes(data)


def assemble(name: str) -> bytes:
    src = ASM / f"{name}.asm"
    dst = OUT / f"{name}.bin"
    lst = OUT / f"{name}.lst"
    cmd = [str(ASM6F), str(src), str(dst), "-l", str(lst)]
    result = subprocess.run(cmd, cwd=ASM, text=True, capture_output=True)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode != 0:
        raise SystemExit(f"assembly failed: {name}")
    return dst.read_bytes()


def read_labels(listing: Path) -> dict[str, int]:
    labels: dict[str, int] = {}
    for line in listing.read_text(encoding="utf-8", errors="ignore").splitlines():
        m = re.match(r"^0([0-9A-Fa-f]{4})\s+([A-Za-z_][A-Za-z0-9_]*):", line)
        if m:
            labels[m.group(2)] = int(m.group(1), 16)
    return labels


def listing_bytes(listing: Path, ranges) -> dict[int, int]:
    """Map every assembled byte address in the given ranges to its value."""
    out: dict[int, int] = {}
    for line in listing.read_text(encoding="utf-8", errors="ignore").splitlines():
        m = re.match(r"^0([0-9A-Fa-f]{4})\s+((?:[0-9A-Fa-f]{2}\s+)+)", line)
        if not m:
            continue
        addr = int(m.group(1), 16)
        data = bytes(int(x, 16) for x in m.group(2).split())
        for i, b in enumerate(data):
            a = addr + i
            if any(lo <= a <= hi for lo, hi in ranges):
                out[a] = b
    return out


def assembled_twice(listing: Path) -> list[int]:
    """Addresses that two .base blocks of the listing both assemble."""
    seen: set[int] = set()
    twice: list[int] = []
    for line in listing.read_text(encoding="utf-8", errors="ignore").splitlines():
        m = re.match(r"^0([0-9A-Fa-f]{4})\s+((?:[0-9A-Fa-f]{2}\s+)+)", line)
        if not m:
            continue
        addr = int(m.group(1), 16)
        for i in range(len(m.group(2).split())):
            if addr + i in seen:
                twice.append(addr + i)
            seen.add(addr + i)
    return sorted(twice)


def write_hook_constants(labels: dict[str, int]) -> None:
    need = ("main_prg", "nmi_prg", "irq_handler", "far_head", "call_hack", "c343_hook",
            "ef08_hook", "ef08_gate", "ef31_hook", "ef31_gate", "chr1_scene", "wait_text", "scroll_text",
            "page_flip", "window_clear", "ltg_copied", "battle_shake",
            "call_ui", "call_ui_army", "bs_wait")
    for label in need:
        if label not in labels:
            raise SystemExit(f"missing fixed-hook label {label}")
    lines = ["; generated by tools/kanji_build.py from mmc3_b15.lst"]
    for label in need:
        lines.append(f"{label.upper()} = ${labels[label]:04X}")
    # The UI functions and flags (kanji.inc) for bank 14's step-B sites.
    inc = ROOT / "decomp" / "include" / "kanji.inc"
    for line in inc.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^(UIF_[A-Z_]+|UI_RAM|UI_NOMIR)\s*=\s*(\S+)", line)
        if m:
            lines.append(f"{m.group(1)} = {m.group(2)}")
    # The canvas RAM code's battle window CALL (bank 14's reward template).
    cv = read_labels(OUT / "canvas_ram.lst")
    lines.append(f"CV_WINCB = ${cv['cv_wincb']:04X}")
    # The map UI's labels (bank 14's gold window and その他: TXF_LABEL).
    lines.append(f"TXR_CALL = ${cv['txr_call']:04X}")
    for line in inc.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^(TXR_ON|TXR_TA|TXR_TX|TXF_LABEL)\s*=\s*(\S+)", line)
        if m:
            lines.append(f"{m.group(1)} = {m.group(2)}")
    text = "".join(line + "\n" for line in lines)
    (OUT / "fixed_hooks.inc").write_text(text, encoding="utf-8")


def build_font() -> bytes:
    sys.path.insert(0, str(ROOT / "tools"))
    import kanji_font
    kanji_font.build()
    return (OUT / "kanji_font.bin").read_bytes()


def glyph_tables(font: bytes, first: int) -> bytes:
    """32 tables of GLYPHS_PER_BANK bytes: table b = byte b of every glyph.

    The source font is 32 bytes per glyph, 16 rows of (left, right).  Byte b
    of the table layout is tile k = b >> 3 (TL, TR, BL, BR), row r = b & 7.
    """
    out = bytearray(32 * GLYPHS_PER_BANK)
    for b in range(32):
        k, r = b >> 3, b & 7
        src = ((k >> 1) * 8 + r) * 2 + (k & 1)
        for local in range(GLYPHS_PER_BANK):
            g = first + local
            if (g + 1) * 32 <= len(font):
                out[b * GLYPHS_PER_BANK + local] = font[g * 32 + src]
    return bytes(out)


def relocated_palettes() -> bytes:
    """The game's palette tables, moved to PAL_DATA with the pointers fixed."""
    fixed = prg()[15 * 0x4000:16 * 0x4000]
    lo, hi = PALETTE_TABLES
    block = bytearray(fixed[lo - 0xC000:hi - 0xC000])
    plo, phi, count = PALETTE_PTRS
    for i in range(count):
        a = block[plo - lo + i] | (block[phi - lo + i] << 8)
        if not lo <= a < hi:
            raise SystemExit(f"palette pointer {i} = ${a:04X} outside the tables")
        a = a - lo + PAL_DATA
        block[plo - lo + i] = a & 0xFF
        block[phi - lo + i] = a >> 8
    # Set 8: P2 = $03E8-$03EB.  The record is <first $03E0 index> <colours>
    # <terminator with bit 7>.
    rec = (fixed[plo - 0xC000 + 8] | (fixed[phi - 0xC000 + 8] << 8)) - lo
    first = block[rec]
    colours = []
    i = rec + 1
    while block[i] < 0x80:
        colours.append(i)
        i += 1
    if not (first <= 8 and first + len(colours) >= 12):
        raise SystemExit("palette set 8 does not cover P2")
    at = colours[8 - first:12 - first]
    if bytes(block[j] for j in at) != bytes((0x0F, 0x17, 0x0F, 0x17)):
        raise SystemExit("palette set 8 P2 is not the audited 0F 17 0F 17")
    for j, v in zip(at, PAL_SET8_P2):
        block[j] = v
    return bytes(block)


def build_hack_banks(font: bytes) -> None:
    code = assemble("hack")
    # The assembler emitted the code and the .org $8800 padding.
    if len(code) < GLYPH_BASE - 0x8000:
        code = code + bytes(GLYPH_BASE - 0x8000 - len(code))
    if any(code[HACK_CODE_LIMIT:HACK_CODE2 - 0x8000]):
        raise SystemExit(f"hack code is over {HACK_CODE_LIMIT} bytes")
    if len(code) > PAL_DATA - 0x8000:
        raise SystemExit("second hack code segment runs into the palette tables")
    global HACK_BANKS
    glyphs = len(font) // 32
    nbanks = max(2, -(-glyphs // GLYPHS_PER_BANK))
    if 23 + nbanks - 1 > 30:
        raise SystemExit(f"{glyphs} glyphs need {nbanks} hack banks (23-30 available)")
    HACK_BANKS = tuple(range(23, 23 + nbanks))
    palettes = relocated_palettes()
    for slot, bank in enumerate(HACK_BANKS):
        data = bytearray(0x4000)
        data[:HACK_CODE_LIMIT] = code[:HACK_CODE_LIMIT]
        tables = glyph_tables(font, slot * GLYPHS_PER_BANK)
        start = GLYPH_BASE - 0x8000
        if start + len(tables) > 0x4000:
            raise SystemExit("glyph tables overflow the hack bank")
        data[start:start + len(tables)] = tables
        if start + len(tables) > PAL_DATA - 0x8000:
            raise SystemExit("glyph tables overlap the relocated palette tables")
        data[PAL_DATA - 0x8000:PAL_DATA - 0x8000 + len(palettes)] = palettes
        # Second code segment ($B900-$BEFF), identical in every hack bank.
        if start + len(tables) > HACK_CODE2 - 0x8000:
            raise SystemExit("glyph tables overlap the second hack code segment")
        seg2 = code[HACK_CODE2 - 0x8000:PAL_DATA - 0x8000]
        data[HACK_CODE2 - 0x8000:HACK_CODE2 - 0x8000 + len(seg2)] = seg2
        write_bank(f"bank{bank:02d}.bin", bytes(data))


def build_ui_block() -> None:
    """The kanji target's copy of the bank-9 UI block (decision 11)."""
    src = ROOT / "decomp" / "build" / "assets" / "bank09_ui_b.bin"
    data = bytearray(src.read_bytes())
    if len(data) != 0x200:
        raise SystemExit(f"{src.name}: {len(data)} bytes, expected 512")
    for tile in UI_BLOCK_PLANE1:
        o = (tile - 0xE0) * 16
        p0, p1 = bytes(data[o:o + 8]), data[o + 8:o + 16]
        if any(p1):
            raise SystemExit(f"UI block tile ${tile:02X} already has plane 1")
        data[o:o + 8] = bytes(8)
        data[o + 8:o + 16] = p0
    (OUT / "bank09_ui_b_k.bin").write_bytes(bytes(data))


def _game_string(bank: bytes, off: int) -> bytes:
    out = bytearray()
    while bank[off] != 0xFF:
        out.append(bank[off])
        off += 1
    return bytes(out)


def build_ui_data() -> int:
    """ui_data.inc: the UI glyphs (the labels first, in slot order, then 計),
    the tactic and item kanji tables and the こうげき table.  Returns the
    glyph count."""
    sys.path.insert(0, str(ROOT / "tools"))
    import kanji_common
    import textdata
    rom = prg()
    b12 = rom[12 * 0x4000:13 * 0x4000]
    b14 = rom[14 * 0x4000:15 * 0x4000]

    def kana_of(raw: bytes) -> str:
        return "".join(textdata.BYTE_TO_CHAR.get(b, "?") for b in raw)

    by_kana: dict[str, tuple[str, str]] = {}
    for typ, kana, kanji in kanji_common.wordlist():
        by_kana.setdefault(kana, (typ, kanji))
    glyphs: list[str] = list(kanji_common.UI_LABELS) + ["計"]

    def gid(ch: str) -> int:
        if ch not in glyphs:
            glyphs.append(ch)
        return glyphs.index(ch)

    lines = ["; generated by tools/kanji_build.py (build_ui_data): UI glyphs and tables",
             f"UI_G_KEI = {glyphs.index('計')}"]
    # Tactics: bank 12 $A700/$A720 -> kana name (without のけい); the word
    # list has "XXのけい" -> "AB の計": glyphs A and B ($FF: none).
    g1, g2 = [0xFF] * 32, [0xFF] * 32
    for i in range(32):
        ptr = b12[0x2700 + i] | (b12[0x2720 + i] << 8)
        if not 0x8000 <= ptr < 0xC000:
            continue
        kana = kana_of(_game_string(b12, ptr - 0x8000))
        ent = by_kana.get(kana + "のけい")
        if ent is None:
            continue
        ks = kanji_common.KANJI_RE.findall(ent[1])
        if not ent[1].endswith("の計") or len(ks) != 3:
            raise SystemExit(f"tactic {i:02X} {kana}: unexpected kanji {ent[1]}")
        g1[i], g2[i] = gid(ks[0]), gid(ks[1])
    lines.append("ui_tactic_g1:")
    lines += [".db " + ",".join(f"${v:02X}" for v in g1[j:j + 16]) for j in (0, 16)]
    lines.append("ui_tactic_g2:")
    lines += [".db " + ",".join(f"${v:02X}" for v in g2[j:j + 16]) for j in (0, 16)]
    if sorted(UI_FIXED) != sorted(kanji_common.UI_COMMANDS) or len(set(UI_FIXED)) != 15:
        raise SystemExit("UI_FIXED must hold the 15 command kanji once each")
    lines.append("ui_fixed_g:")
    lines.append(".db " + ",".join(f"${gid(ch):02X}" for ch in UI_FIXED)
                 + "  ; " + UI_FIXED)
    # The reward window: each kanji's UI glyph and its text code (the code a
    # message's pool slot records in UI_MC_LO/HI).
    codes = kanji_common.code_map()
    missing = [ch for ch in REWARD_KANJI if ch not in codes]
    if missing:
        raise SystemExit(f"reward kanji without a text code: {''.join(missing)}")
    lines.append("ui_reward_g:")
    lines.append(".db " + ",".join(f"${gid(ch):02X}" for ch in REWARD_KANJI)
                 + "  ; " + REWARD_KANJI)
    lines.append("ui_reward_clo:")
    lines.append(".db " + ",".join(f"${codes[ch] & 0xFF:02X}" for ch in REWARD_KANJI))
    lines.append("ui_reward_chi:")
    lines.append(".db " + ",".join(f"${codes[ch] >> 8:02X}" for ch in REWARD_KANJI))
    # The army status screen's M S P ($F5-$F7): plane 0 of the original
    # bank-9 UI block (the kanji target's copy has them in plane 1).
    blk = (ROOT / "decomp" / "build" / "assets" / "bank09_ui_b.bin").read_bytes()
    smp = b"".join(blk[(t - 0xE0) * 16:(t - 0xE0) * 16 + 8] for t in (0xF5, 0xF6, 0xF7))
    if not all(smp[i * 8:i * 8 + 8] for i in range(3)) or any(
            blk[(t - 0xE0) * 16 + 8:(t - 0xE0) * 16 + 16] != bytes(8) for t in (0xF5, 0xF6, 0xF7)):
        raise SystemExit("bank-9 UI block: M S P are not plane-0 glyphs")
    lines.append("ui_army_smp:")
    lines.append(".db " + ",".join(f"${b:02X}" for b in smp) + "  ; M S P, plane 0")
    # Items: bank 12 $A3C8/$A438 -> name at +2.  Equipment with a word-list
    # entry: its kanji (glyph ids; kana as $FE <game code>), else the kana
    # name; $FF ends.
    strings: dict[bytes, str] = {}
    item_labels = []
    for i in range(0x80):
        ptr = b12[0x23C8 + i] | (b12[0x2438 + i] << 8)
        raw = _game_string(b12, ptr + 2 - 0x8000) if 0x8000 <= ptr < 0xC000 else b""
        ent = by_kana.get(kana_of(raw))
        enc = bytearray()
        if ent and ent[0] in UI_ITEM_TYPES:
            for ch in ent[1]:
                if kanji_common.KANJI_RE.fullmatch(ch):
                    enc.append(gid(ch))
                else:
                    enc += bytes((0xFE, textdata.CHAR_TO_BYTE[ch]))
        else:
            for b in raw:
                enc += bytes((0xFE, b))
        enc.append(0xFF)
        key = bytes(enc)
        if key not in strings:
            strings[key] = f"ui_item_s{len(strings)}"
        item_labels.append(strings[key])
    lines.append("ui_item_lo:")
    lines += [".db " + ",".join(f"<{x}" for x in item_labels[j:j + 8]) for j in range(0, 0x80, 8)]
    lines.append("ui_item_hi:")
    lines += [".db " + ",".join(f">{x}" for x in item_labels[j:j + 8]) for j in range(0, 0x80, 8)]
    for key, label in strings.items():
        lines.append(f"{label}: .db " + ",".join(f"${b:02X}" for b in key))
    # こうげき: the info screen reads b14 $8602 + $60C0[actor] (256 bytes
    # copied, so any index reads what the original reads).
    lines.append("ui_atk_table:")
    atk = b14[0x0602:0x0702]
    lines += [".db " + ",".join(f"${b:02X}" for b in atk[j:j + 16]) for j in range(0, 256, 16)]
    attr = bytearray(64)
    for pal, r0, r1, c0, c1 in INFO_ATTR_CELLS:
        for r in range(r0 // 2, r1 // 2 + 1):
            for c in range(c0 // 2, c1 // 2 + 1):
                shift = ((r & 1) * 2 + (c & 1)) * 2
                i = (r // 2) * 8 + c // 2
                attr[i] = (attr[i] & ~(3 << shift)) | (pal << shift)
    lines.append("ui_info_attr:")
    lines += [".db " + ",".join(f"${b:02X}" for b in attr[j:j + 16]) for j in range(0, 64, 16)]
    if len(glyphs) > 0xF0:
        raise SystemExit(f"{len(glyphs)} UI glyphs, max 240")
    # Glyphs in tile order t, t+1, t+2, t+3 = TL, BL, TR, BR (decision 3),
    # 8 rows each.
    lines.append(f"UI_NGLYPHS = {len(glyphs)}")
    lines.append("ui_glyphs:")
    for ch in glyphs:
        g = kanji_common.glyph_bytes(ch)
        tl = [g[r * 2] for r in range(8)]
        tr = [g[r * 2 + 1] for r in range(8)]
        bl = [g[(8 + r) * 2] for r in range(8)]
        br = [g[(8 + r) * 2 + 1] for r in range(8)]
        lines.append(".db " + ",".join(f"${b:02X}" for b in tl + bl + tr + br)
                     + f"  ; U+{ord(ch):04X}")
    (OUT / "ui_data.inc").write_text("".join(x + "\n" for x in lines), encoding="utf-8")
    return len(glyphs)


# Map-mode UI (TEXT_RENDERER.md "Kanji UI"): window template changes for
# the kanji forms (window -> (column offset, width)).  A template's bytes
# are the row offset, the column offset (both in metatiles: windows start
# on even columns) and the width.  The map's redraw, which closes windows,
# covers screen columns 2-29 only, so no window may reach column 30.  The
# gold window $18 (columns 20-29) becomes 12 wide at columns 18-29: 金 /
# 兵糧 in 16x16 kanji from column 20 (the item list's border, column 19,
# is drawn over this window when the list opens again), the number right
# aligned at column 28 (6 digits).  $1C (columns 22-29) becomes 10 wide at
# 20-29 for 買いに来た.
MAP_UI_TEMPLATES = {0x18: (1, 12), 0x1C: (2, 10)}
# The labels TXF_LABEL writes (kanji_common.MAP_UI_LABELS order): the first
# cell's offset from the row-buffer index passed in, and the index after.
MAP_UI_LABEL_POS = ((0, 3), (0, 3), (0, 4))


def build_txr_ui() -> None:
    """txr_ui.inc (bank 26): the map UI's kanji strings.  Template words by
    window and text_col; item names by record pointer (strings from byte
    2), tactic and place names (from byte 0); the labels.  String bytes:
    a kana byte as the game's, $EC n = UI kanji n (glyph code ui_gc), $FF
    ends."""
    sys.path.insert(0, str(ROOT / "tools"))
    import kanji_common
    import textdata
    rom = prg()
    b12 = rom[12 * 0x4000:13 * 0x4000]
    b14 = rom[14 * 0x4000:15 * 0x4000]
    b15 = rom[15 * 0x4000:16 * 0x4000]
    codes = kanji_common.code_map()
    glyphs: list[str] = []
    strings: dict[bytes, str] = {}

    def cells(text: str) -> int:
        return sum(2 if kanji_common.KANJI_RE.fullmatch(ch) else 1 for ch in text)

    def enc(text: str) -> str:
        out = bytearray()
        for ch in text:
            if kanji_common.KANJI_RE.fullmatch(ch):
                if ch not in codes:
                    raise SystemExit(f"map UI kanji {ch} has no text code")
                if ch not in glyphs:
                    glyphs.append(ch)
                out += bytes((0xEC, glyphs.index(ch)))
            else:
                b = textdata.CHAR_TO_BYTE[ch]
                if b >= 0xEC:
                    raise SystemExit(f"map UI kana {ch} encodes as ${b:02X}")
                out.append(b)
        out.append(0xFF)
        key = bytes(out)
        if key not in strings:
            strings[key] = f"ui_s{len(strings)}"
        return strings[key]

    def kana_bytes(text: str) -> bytes:
        return bytes(textdata.CHAR_TO_BYTE[ch] for ch in text)

    def rd(addr: int) -> int:
        return b15[addr - 0xC000] if addr >= 0xC000 else b14[addr - 0x8000]

    lines = ["; generated by tools/kanji_build.py (build_txr_ui): the map UI's kanji"]
    # Templates: the word's first byte (text_col) -> skip, string.  The
    # width check follows text_input: a line after $FA starts at index 2,
    # after $FB at 1; the last text cell is width - 2.
    by_win: dict[int, list[tuple[int, int, str]]] = {}
    for win, kana, kanji in kanji_common.MAP_UI_WORDS:
        ptr = b15[0x2DA1 + win] | (b15[0x2DD1 + win] << 8)
        width = MAP_UI_TEMPLATES.get(win, (0, rd(ptr + 2)))[1]
        tpl = bytes(rd(ptr + i) for i in range(64))
        want = kana_bytes(kana)
        off = tpl.find(want, 3)
        end = tpl.find(bytes((0xFF,)), 3)
        if off < 0 or off > end or 0 <= tpl.find(want, off + 1) < end:
            raise SystemExit(f"window ${win:02X}: {kana} not found once")
        i, col = 3, None
        while i < off:
            b = tpl[i]
            if b == 0xF8:
                i += 3
                continue
            if b >= 0xFA:
                col = 2 if b == 0xFA else 1
            elif col is not None:
                col += 1
            i += 1
        if col is None or col + cells(kanji) - 1 > width - 2:
            raise SystemExit(f"window ${win:02X}: {kanji} does not fit (width {width})")
        by_win.setdefault(win, []).append((off, len(want) - 1, enc(kanji)))
    lines.append("UI_NWIN = $30")
    lines.append("ui_win_lo:")
    lines.append(".db " + ",".join(f"<ui_w{w:02X}" if w in by_win else "0" for w in range(0x30)))
    lines.append("ui_win_hi:")
    lines.append(".db " + ",".join(f">ui_w{w:02X}" if w in by_win else "0" for w in range(0x30)))
    for win, ents in sorted(by_win.items()):
        lines.append(f"ui_w{win:02X}: .db " + ",".join(
            f"{o},{k},<{lab},>{lab}" for o, k, lab in sorted(ents)) + ",$FF")

    def record(ptr: int, start: int) -> bytes:
        o = ptr - 0x8000 + start
        return bytes(b12[o:b12.index(0xFF, o)])

    def kana_of(raw: bytes) -> str:
        return "".join(textdata.BYTE_TO_CHAR.get(b, "?") for b in raw)

    by_kana: dict[str, str] = {}
    for _typ, kana, kanji in kanji_common.wordlist():
        by_kana.setdefault(kana, kanji)
    # Items: pointers $A3C8 / $A438 + i, the name from byte 2.
    r2: dict[int, tuple[int, str]] = {}
    missing = []
    for i in range(0x70):
        ptr = b12[0x23C8 + i] | (b12[0x2438 + i] << 8)
        if not 0x8000 <= ptr < 0xC000 or ptr in r2:
            continue
        raw = record(ptr, 2)
        kanji = by_kana.get(kana_of(raw))
        if kanji is None:
            if kana_of(raw) not in missing:
                missing.append(kana_of(raw))
            continue
        r2[ptr] = (len(raw) - 1, enc(kanji))
    # Tactics ($A700 / $A720 + i, from byte 0; the word list's "XXのけい"
    # is "AB の計": the name is AB) and places (kanji_common.map_places).
    r0: dict[int, tuple[int, str]] = {}
    for i in range(32):
        ptr = b12[0x2700 + i] | (b12[0x2720 + i] << 8)
        if not 0x8000 <= ptr < 0xC000 or ptr in r0:
            continue
        raw = record(ptr, 0)
        kanji = by_kana.get(kana_of(raw) + "のけい")
        if kanji is None or not kanji.endswith("の計"):
            missing.append(kana_of(raw) + "のけい")
            continue
        r0[ptr] = (len(raw) - 1, enc(kanji[:-2]))
    for i, (raw, kanji) in sorted(kanji_common.map_places().items()):
        ptr = b12[0x2100 + i] | (b12[0x2140 + i] << 8)
        if ptr not in r0:
            r0[ptr] = (len(raw) - 1, enc(kanji))
    for name, tab in (("r2", r2), ("r0", r0)):
        keys = sorted(tab)
        if not 0 < len(keys) < 128:
            raise SystemExit(f"map UI table {name}: {len(keys)} records")
        lines.append(f"UI_N{name[1]} = {len(keys)}")
        lines.append(f"ui_{name}_lo: .db " + ",".join(f"${k & 0xFF:02X}" for k in keys))
        lines.append(f"ui_{name}_hi: .db " + ",".join(f"${k >> 8:02X}" for k in keys))
        lines.append(f"ui_{name}_sk: .db " + ",".join(str(tab[k][0]) for k in keys))
        lines.append(f"ui_{name}_sl: .db " + ",".join(f"<{tab[k][1]}" for k in keys))
        lines.append(f"ui_{name}_sh: .db " + ",".join(f">{tab[k][1]}" for k in keys))
    labs = [enc(t) for t in kanji_common.MAP_UI_LABELS]
    if len(labs) != len(MAP_UI_LABEL_POS):
        raise SystemExit("MAP_UI_LABEL_POS does not match MAP_UI_LABELS")
    lines.append("ui_lb_off: .db " + ",".join(f"${o & 0xFF:02X}" for o, _ in MAP_UI_LABEL_POS))
    lines.append("ui_lb_adv: .db " + ",".join(str(a) for _, a in MAP_UI_LABEL_POS))
    lines.append("ui_lb_lo: .db " + ",".join(f"<{x}" for x in labs))
    lines.append("ui_lb_hi: .db " + ",".join(f">{x}" for x in labs))
    if len(glyphs) > 0x100:
        raise SystemExit(f"{len(glyphs)} map UI kanji, max 256")
    lines.append(f"UI_NGC = {len(glyphs)}")
    for j in range(0, len(glyphs), 16):
        part = glyphs[j:j + 16]
        lines.append(("ui_gc_lo: " if j == 0 else "") + ".db "
                     + ",".join(f"${codes[ch] & 0xFF:02X}" for ch in part))
    for j in range(0, len(glyphs), 16):
        part = glyphs[j:j + 16]
        lines.append(("ui_gc_hi: " if j == 0 else "") + ".db "
                     + ",".join(f"${codes[ch] >> 8:02X}" for ch in part))
    for key, label in strings.items():
        lines.append(f"{label}: .db " + ",".join(f"${b:02X}" for b in key))
    (OUT / "txr_ui.inc").write_text("".join(x + "\n" for x in lines), encoding="utf-8")
    (OUT / "txr_ui_missing.txt").write_text("".join(x + "\n" for x in missing), encoding="utf-8")


def write_ui_bank(image: bytes) -> None:
    if UI_BANK in HACK_BANKS:
        raise SystemExit(f"the font's hack banks {HACK_BANKS} reach bank {UI_BANK}")
    if any((OUT / f"bank{UI_BANK:02d}.bin").read_bytes()):
        raise SystemExit(f"bank {UI_BANK} (the UI bank) holds other data")
    if len(image) > 0x4000:
        raise SystemExit(f"UI bank image is {len(image)} bytes")
    write_bank(f"bank{UI_BANK:02d}.bin", image + bytes(0x4000 - len(image)))


def build_canvas_ram() -> bytes:
    image = assemble("canvas_ram")
    labels = read_labels(OUT / "canvas_ram.lst")
    if len(image) > CV_RAM_PAGES * 0x100:
        raise SystemExit(f"canvas RAM code is {len(image)} bytes, "
                         f"max {CV_RAM_PAGES * 0x100}")
    if CV_RAM + len(image) > TXR_TABLES:
        raise SystemExit(f"RAM code ends at ${CV_RAM + len(image):04X}, "
                         f"past the text renderer's tables at ${TXR_TABLES:04X}")
    lines = ["; generated by tools/kanji_build.py from canvas_ram.lst"]
    for label in CV_LABELS:
        if label not in labels:
            raise SystemExit(f"missing canvas label {label}")
        lines.append(f"{label.upper()} = ${labels[label]:04X}")
    (OUT / "canvas_ram.inc").write_text("".join(x + "\n" for x in lines),
                                       encoding="utf-8")
    return image


def write_canvas_bank(image: bytes) -> None:
    if CV_BANK in HACK_BANKS:
        raise SystemExit(f"the font's hack banks {HACK_BANKS} reach bank {CV_BANK}")
    if any((OUT / f"bank{CV_BANK:02d}.bin").read_bytes()):
        raise SystemExit(f"bank {CV_BANK} (the canvas RAM image) holds other data")
    data = bytearray(0x4000)
    data[0x2000:0x2000 + len(image)] = image
    write_bank(f"bank{CV_BANK:02d}.bin", bytes(data))


def write_txr_bank(image: bytes) -> None:
    if TXR_BANK in HACK_BANKS:
        raise SystemExit(f"the font's hack banks {HACK_BANKS} reach bank {TXR_BANK}")
    if any((OUT / f"bank{TXR_BANK:02d}.bin").read_bytes()):
        raise SystemExit(f"bank {TXR_BANK} (the text renderer) holds other data")
    if len(image) > 0x4000:
        raise SystemExit(f"text renderer image is {len(image)} bytes")
    write_bank(f"bank{TXR_BANK:02d}.bin", image + bytes(0x4000 - len(image)))


def build_overlay(overlay: bytes) -> None:
    if len(overlay) > OVERLAY_LIMIT:
        raise SystemExit(f"overlay is {len(overlay)} bytes, max {OVERLAY_LIMIT}")
    if len(overlay) < OVERLAY_LIMIT:
        overlay = overlay + bytes(OVERLAY_LIMIT - len(overlay))
    (OUT / "kanji_overlay_padded.bin").write_bytes(overlay)


def apply_patch(bank: bytearray, addr: int, data: bytes) -> None:
    off = addr - 0xC000
    original = bytes(bank[off:off + len(data)])
    want = PATCH_SITES.get(addr)
    if want is not None and original != want:
        raise SystemExit(f"patch site ${addr:04X}: expected {want.hex()}, "
                         f"found {original.hex()}")
    bank[off:off + len(data)] = data


def build_bank15(fixed: bytes, labels: dict[str, int],
                 overlay_labels: dict[str, int]) -> None:
    original = prg()
    bank = bytearray(original[15 * 0x4000:16 * 0x4000])

    # Assemble the dispatcher bytes into their audited gaps.  Every byte the
    # fixed-bank source assembles must fall inside one of them.
    everything = listing_bytes(OUT / "mmc3_b15.lst", ((0xC000, 0xFFFF),))
    twice = assembled_twice(OUT / "mmc3_b15.lst")
    if twice:
        raise SystemExit(f"fixed-bank blocks overlap at ${twice[0]:04X}")
    inside = listing_bytes(OUT / "mmc3_b15.lst", HOOK_RANGES)
    spill = sorted(set(everything) - set(inside))
    if spill:
        raise SystemExit(f"fixed-bank hook code outside its gaps at ${spill[0]:04X}")
    a, b, digest = PALETTE_REGION
    if hashlib.sha256(bytes(bank[a - 0xC000:b - 0xC000])).hexdigest() != digest:
        raise SystemExit(f"palette region ${a:04X}-${b - 1:04X} differs from the audited original")
    for lo, hi, digest in FOURSCREEN_REGIONS:
        if hashlib.sha256(bytes(bank[lo - 0xC000:hi - 0xC000 + 1])).hexdigest() != digest:
            raise SystemExit(f"four-screen region ${lo:04X}-${hi:04X} differs from the audited original")
    for lo, hi, digest in QOL_REGIONS:
        if hashlib.sha256(bytes(bank[lo - 0xC000:hi - 0xC000 + 1])).hexdigest() != digest:
            raise SystemExit(f"QoL region ${lo:04X}-${hi:04X} differs from the audited original")
    if labels["cpt_stub"] != 0xD671:
        raise SystemExit(f"cpt_stub at ${labels['cpt_stub']:04X}: copy_pointer_triplet is $D671")
    if labels["div_stub"] != 0xC1D2:
        raise SystemExit(f"div_stub at ${labels['div_stub']:04X}: div24_shift is $C1D2")
    base, want = RESET_REGION
    have = bytes(bank[base - 0xC000:base - 0xC000 + len(want)])
    if have != want:
        raise SystemExit(f"reset region ${base:04X}: expected {want.hex()}, found {have.hex()}")
    for addr, value in inside.items():
        bank[addr - 0xC000] = value

    # MMC3 bank switches (revision 21).  set_bank_lock keeps its
    # "sta current_prg_bank" and jumps to main_prg; restore_bank_after_nmi
    # (NMI only) jumps to nmi_prg.  The rest of both bodies, mmc1_reset
    # and write_prg_bank are dead: nothing else calls them.
    apply_patch(bank, 0xC486, bytes((0x4C, labels["main_prg"] & 0xFF,
                                     labels["main_prg"] >> 8)))
    apply_patch(bank, 0xC4AA, bytes((0x4C, labels["nmi_prg"] & 0xFF,
                                     labels["nmi_prg"] >> 8)))

    # Text-engine hooks (extended dispatcher and page control).
    apply_patch(bank, 0xD28E, bytes((0x4C, overlay_labels["text_dispatch"] & 0xFF,
                                     overlay_labels["text_dispatch"] >> 8)))
    apply_patch(bank, 0xD2C7, bytes((0x20, overlay_labels["ctrl_store"] & 0xFF,
                                     overlay_labels["ctrl_store"] >> 8)))

    # return_inline_block popped its return address and then read it from
    # the freed stack bytes: an interrupt between (the map's IRQs, 4 a
    # frame) overwrote them and the game jumped into page 1.  The same
    # bytes, the reads first.
    apply_patch(bank, 0xC4FD, bytes.fromhex("babd010185f3bd020185f46868"))

    # The map UI in kanji (TEXT_RENDERER.md "Kanji UI"): text_put_tile's
    # calls in the templates and the item / tactic / place names go through
    # txr_tp (the renderer in map mode); MAP_UI_TEMPLATES' windows change.
    for site in (0xCC02, 0xD5C0):
        apply_patch(bank, site, bytes((0x20, labels["txr_tp"] & 0xFF,
                                       labels["txr_tp"] >> 8)))
    for win, (col, w) in MAP_UI_TEMPLATES.items():
        ptr = bank[0x2DA1 + win] | (bank[0x2DD1 + win] << 8)
        apply_patch(bank, ptr + 1, bytes((col & 0xFF, w)))

    # NMI: after the nmi_mode branch (normal frames) and the epilogue.  No
    # byte before the game's split-screen loops changes.
    apply_patch(bank, 0xEF0B, bytes((0x4C, labels["ef08_gate"] & 0xFF,
                                     labels["ef08_gate"] >> 8, 0xEA, 0xEA)))
    apply_patch(bank, 0xEF31, bytes((0x4C, labels["ef31_gate"] & 0xFF,
                                     labels["ef31_gate"] >> 8)))

    # Kanji page flip after the <PAGE> wait.
    apply_patch(bank, 0xD1C8, bytes((0x20, labels["page_flip"] & 0xFF,
                                     labels["page_flip"] >> 8)))

    # Block-writer hook.  The canvas RAM code's cv_stream calls its plain
    # body at a fixed address (canvas_ram.asm C343_PLAIN).
    if labels["c343_plain"] != 0xFFE0:
        raise SystemExit(f"c343_plain moved to ${labels['c343_plain']:04X}: "
                         "update C343_PLAIN in canvas_ram.asm")
    apply_patch(bank, 0xC343, bytes((0x4C, labels["c343_hook"] & 0xFF,
                                     labels["c343_hook"] >> 8)))

    # The MMC3 scanline IRQ switches the band page (revision 21b); the
    # original's IRQ vector pointed at the NMI handler (no IRQ source).
    # Sprite 0 and clear_oam_shadow are the game's own again.
    apply_patch(bank, 0xFFFE, bytes((labels["irq_handler"] & 0xFF,
                                     labels["irq_handler"] >> 8)))

    # text_render_cell draws the battle pool's kanji tiles ($A4-$DF), which
    # have bit 7 set like the row buffer's end codes (revision 18).
    # text_redraw_lines (the window scroll) blanks every cell with bit 7
    # set, so the battle pool's kanji vanished from scrolled lines.  Only
    # the line-end codes ($FA-$FF) are blanked now; the original rows hold
    # nothing else at $80 and up (revision 20).  Same 17 bytes:
    #   lda $F4 / cmp #7 / lda #$0A / bcs store / lda $0319,x / cmp #$FA /
    #   bcc store / lda #$0A
    apply_patch(bank, 0xD416, bytes.fromhex("a5f4c907a90ab009bd1903c9fa9002a90a"))

    apply_patch(bank, 0xDBED, bytes((labels["render_ctl"] & 0xFF,
                                     labels["render_ctl"] >> 8)))

    # Battle windows (step B item 7): one UI-bank CALL per line,
    # "$F8 cv_wincb n" (ui_battle.asm); the tactic window's title のこり
    # becomes 残り (残's lower half, group 20 = tiles $F4-$F7; its upper half
    # is written in row 17 by UIF_SM).
    if labels["call_ui"] != 0xC48D:
        raise SystemExit(f"call_ui moved to ${labels['call_ui']:04X}: "
                         "update CALL_UI_C in canvas_ram.asm")
    cv = read_labels(OUT / "canvas_ram.lst")
    cb = bytes((0xF8, cv["cv_wincb"] & 0xFF, cv["cv_wincb"] >> 8))
    for addr, data in battle_templates(cb).items():
        apply_patch(bank, addr, data)
    # The reward window $22 (victory) has four lines now, one byte more
    # than its 19-byte template holds: its pointer (data_EDA1/EDD1 + $22)
    # goes to bank 14's b14_k_reward_tpl, in place of the original's
    # b14_wincb_exp_line (only $22 called it; bank 14 is mapped while
    # text_init reads a template, as its CALLs need).
    apply_patch(bank, 0xEDA1 + 0x22, bytes((REWARD_TPL & 0xFF,)))
    apply_patch(bank, 0xEDD1 + 0x22, bytes((REWARD_TPL >> 8,)))

    # Battle setup without frame pacing (QoL): the enemy roll's and the
    # name loop's queue waits call bs_wait (with the NMI busy and the
    # screen off it runs the main task's per-frame steps in place of the
    # frame, so every roll sees the same RNG steps; otherwise the real
    # wait), and the loop's end calls UIF_BSETUP_END (X = $0A at that
    # point) before battle_setup_intro: "cpx #$0A / bne loc_E0A3 /
    # jsr call_ui".  Bank 14's $9BE3 / $9C47 call bs_wait too.
    uif = {}
    for line in (ROOT / "decomp" / "include" / "kanji.inc").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^(UIF_[A-Z_]+)\s*=\s*(\d+)", line)
        if m:
            uif[m.group(1)] = int(m.group(2))
    if uif.get("UIF_BSETUP_END") != 0x0A:
        raise SystemExit("UIF_BSETUP_END must be 10: bank 15 $E10F calls call_ui with X = $0A")
    for addr in BSETUP_WAITS:
        apply_patch(bank, addr, bytes((0x20, labels["bs_wait"] & 0xFF, labels["bs_wait"] >> 8)))
    apply_patch(bank, 0xE10F, bytes((0xE0, 0x0A, 0xD0, 0x90, 0x20,
                                     labels["call_ui"] & 0xFF, labels["call_ui"] >> 8)))

    # The map text renderer (TEXT_RENDERER.md): the RAM stubs.
    def jmp(op, label):
        return bytes((op, cv[label] & 0xFF, cv[label] >> 8))
    apply_patch(bank, 0xDD03, jmp(0x4C, "txr_dlx"))
    apply_patch(bank, 0xDBCA, jmp(0x4C, "txr_rcx"))
    apply_patch(bank, 0xCD07, jmp(0x20, "txr_cur") + bytes((0xEA,)))
    apply_patch(bank, 0xCF22, jmp(0x20, "txr_mi"))


    write_bank("bank15.bin", bytes(bank))


def battle_templates(cb: bytes) -> dict[int, bytes]:
    """Window templates $11, $12 (command windows), $16 (items), $17
    (tactics) with the UI-bank line CALL cb + n."""
    end = bytes((0xFF,))

    def lines(*ns: int) -> bytes:
        return b"".join(bytes((0xFA,)) + cb + bytes((n,)) for n in ns)
    title = bytes.fromhex("6D0C0C0C F5F732 0A F6F7 0A0A0A0A 0C0C0C0C0C6E")
    out = {
        0xEA9C: bytes.fromhex("02FD0F") + lines(0, 1, 2, 3) + end,
        0xEAC8: bytes.fromhex("02FD08") + lines(0, 1, 2, 3) + end,
        0xEB23: bytes.fromhex("02FD14") + lines(0x20, 0x20, 0x20, 0x20) + end,
        0xEB43: (bytes.fromhex("02FD14") + title + bytes.fromhex("FAF88A96")
                 + cb + bytes((0x10,)) + lines(0x10, 0x10) + end),
    }
    room = {0xEA9C: 44, 0xEAC8: 24, 0xEB23: 32, 0xEB43: 48}
    for addr, data in out.items():
        if len(data) > room[addr]:
            raise SystemExit(f"battle template ${addr:04X}: {len(data)} bytes, room {room[addr]}")
    return out


def build_bank31() -> None:
    write_bank("bank31.bin", (OUT / "bank15.bin").read_bytes())


def build_skeleton() -> None:
    blank = bytes(0x4000)
    for bank in range(16, 31):
        path = OUT / f"bank{bank:02d}.bin"
        if not path.exists():
            write_bank(f"bank{bank:02d}.bin", blank)
    for bank in range(25, 31):
        if bank not in HACK_BANKS:
            write_bank(f"bank{bank:02d}.bin", blank)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["build"], nargs="?", default="build")
    ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    canvas = build_canvas_ram()
    fixed = assemble("mmc3_b15")
    labels = read_labels(OUT / "mmc3_b15.lst")
    write_hook_constants(labels)

    font = build_font()
    build_hack_banks(font)
    build_ui_block()
    nglyphs = build_ui_data()
    ui = assemble("ui")
    build_txr_ui()
    txr = assemble("txr")

    trampoline = assemble("trampoline")
    if len(trampoline) > 0x100:
        raise SystemExit(f"trampoline is {len(trampoline)} bytes, max 256")
    (OUT / "far_stub.txt").write_text(
        f"{labels['far_head']:04X}\n", encoding="utf-8")

    overlay = assemble("kanji_overlay")
    overlay_labels = read_labels(OUT / "kanji_overlay.lst")
    build_overlay(overlay)

    build_bank15(fixed, labels, overlay_labels)
    build_bank31()
    build_skeleton()

    sys.path.insert(0, str(ROOT / "tools"))
    import kanji_text
    kanji_text.build()
    write_canvas_bank(canvas)
    write_ui_bank(ui)
    write_txr_bank(txr)

    print(f"fixed hooks: {len(fixed)} bytes; overlay: {len(overlay)} bytes; "
          f"hack code: {(OUT / 'hack.bin').stat().st_size} bytes; "
          f"RAM code: {len(canvas)} bytes; UI bank: {len(ui)} bytes "
          f"({nglyphs} glyphs); text renderer: {len(txr)} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
