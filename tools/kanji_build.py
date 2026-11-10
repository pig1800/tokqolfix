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
CV_LABELS = ("cv_irq", "cv_ctp", "cv_ti", "cv_sm", "cv_nmi", "cv_split",
             "cv_w1", "cv_w2", "cv_stage", "cv_flanks", "cv_force",
             "cv_force_end", "cv_reload", "cv_irq_end", "cv_ram_end",
             "cv_stream", "cv_sforce", "cv_sreload", "cv_fill")

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
}


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
            "page_flip", "window_clear", "ltg_copied", "battle_shake")
    for label in need:
        if label not in labels:
            raise SystemExit(f"missing fixed-hook label {label}")
    lines = ["; generated by tools/kanji_build.py from mmc3_b15.lst"]
    for label in need:
        lines.append(f"{label.upper()} = ${labels[label]:04X}")
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


def build_canvas_ram() -> bytes:
    image = assemble("canvas_ram")
    labels = read_labels(OUT / "canvas_ram.lst")
    if len(image) > CV_RAM_PAGES * 0x100:
        raise SystemExit(f"canvas RAM code is {len(image)} bytes, "
                         f"max {CV_RAM_PAGES * 0x100}")
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


    write_bank("bank15.bin", bytes(bank))


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

    print(f"fixed hooks: {len(fixed)} bytes; overlay: {len(overlay)} bytes; "
          f"hack code: {(OUT / 'hack.bin').stat().st_size} bytes; "
          f"canvas RAM code: {len(canvas)} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
