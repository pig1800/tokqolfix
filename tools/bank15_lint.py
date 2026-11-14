#!/usr/bin/env python3
"""Fail if the kanji target changes the fixed bank outside registered sites.

The fixed bank must keep every original bank-15 byte and address except the
registered patch ranges below (and the four-screen rewrites listed in
kanji_build.py).  It is bank 31 (the MMC3 fixed bank at $C000-$FFFF); since
the debloat (2026-11-14) slot 15 is free and holds JAM ($02) bytes.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ORIGINAL = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
KANJI = ROOT / "decomp" / "build" / "rom_kanji.nes"
# The text banks the compiler filled (kanji_text_report.json data_banks;
# 18-22 before the 2026-11-14 debloat): each holds the same overlay copy.
REPORT = Path(__file__).resolve().parent.parent / "decomp" / "build" / "kanji" / "kanji_text_report.json"
OVERLAY_OFF = 0x3800
OVERLAY_SIZE = 0x800

PATCHES = [
    (0xC460, 0xC47D),   # dead mmc1_reset/mmc1_init: render_ctl, IRQ tail
    (0xC486, 0xC488),   # set_bank_lock: jmp main_prg (MMC3)
    (0xC489, 0xC49D),   # dead rest of set_bank_lock: free
    (0xC4AA, 0xC4AC),   # restore_bank_after_nmi: jmp nmi_prg (MMC3)
    (0xC4AD, 0xC4B9),   # dead rest of restore_bank_after_nmi: chr1_scene
    (0xC5A6, 0xC6D1),   # load_text_graphics (tables moved), MMC3 switches, call_hack, block hook
    (0xC4BA, 0xC4CA),   # NMI EF08 hook (dead write_prg_bank body)
    (0xC343, 0xC345),   # jmp c343_hook
    (0xD28E, 0xD290),   # jmp text_dispatch
    (0xD291, 0xD2B6),   # NMI epilogue hook (dead original $EF-$F7 dispatch)
    (0xD2C7, 0xD2C9),   # jsr ctrl_store
    (0xD1C8, 0xD1CA),   # jsr page_flip (kanji page flip after the <PAGE> wait)
    (0xDBED, 0xDBEE),   # text_render_cell: jmp render_ctl (battle pool tiles)
    (0xD416, 0xD426),   # text_redraw_lines: keep cells below $FA (battle pool scroll)
    (0xEA9C, 0xEAB3),   # window $11 template: UI-bank line CALLs (step B item 7)
    (0xEAC8, 0xEADF),   # window $12 template
    (0xEB23, 0xEB3A),   # window $16 template (battle items)
    (0xEB43, 0xEB6C),   # window $17 template (battle tactics; title 残り)
    (0xEC24, 0xEC31),   # window $21's template (the prisoner window in kanji)
    (0xEDC3, 0xEDC3),   # window $22's template pointer, low (reward window: bank 14 $923C)
    (0xEDF3, 0xEDF3),   # its high byte
    (0xD671, 0xD6C1),   # copy_pointer_triplet + divisor table: UIF_DEC stub, bs_wait, blk_main
    (0xC1D2, 0xC216),   # div24_shift: UIF_DIV stub, blk_fast
    (0xDF32, 0xDF34),   # battle setup's enemy roll: jsr bs_wait (was wait_vblank_queued)
    (0xE0A3, 0xE0A5),   # battle setup's name loop: jsr bs_wait (was wait_vblank_queued)
    (0xE200, 0xE202),   # same (battle_draw_slot_troops)
    (0xE238, 0xE23A),   # same
    (0xE10F, 0xE115),   # slot loop end: cpx #$0A / bne loc_E0A3 / jsr call_ui (UIF_BSETUP_END)
    (0xEED0, 0xEED2),   # jmp nmi_gate (map mode: the uploads first)
    (0xEF0B, 0xEF0F),   # jmp cv_nmi (RAM: bank 26's nmi_cvg) + nop nop
    (0xEF31, 0xEF33),   # jmp ef31_gate
    (0xF004, 0xF039),   # reset: MMC3 registers + hack RAM clear (rewritten)
    (0xFFE0, 0xFFEF),   # block-writer entry, overlay frame wait (padding)
    (0xFFFE, 0xFFFF),   # IRQ vector: irq_handler (MMC3 scanline IRQ)
    # the map text renderer (TEXT_RENDERER.md): RAM stubs
    (0xDD03, 0xDD05),   # text_draw_line's end: jmp txr_dlx
    (0xDBCA, 0xDBCC),   # text_render_cell: jmp txr_rcx
    (0xCD07, 0xCD0A),   # text_draw_cursor's tile store: jsr txr_cur / nop
    (0xCF22, 0xCF24),   # screen_refresh's font load (map setup): jsr txr_mi
    # the map UI in kanji: text_put_tile's calls, two templates
    (0xCC02, 0xCC04),   # text_input: jsr txr_tp
    (0xD5C0, 0xD5C2),   # draw_string_from_pointer: jsr txr_tp
    (0xD4C0, 0xD4C2),   # put_officer_name: jsr txr_tp (officer names)
    (0xEB74, 0xEB75),   # window $18 (gold, food): column +1, width 12
    (0xEBCF, 0xEBD0),   # window $1C (buy / sell): column +2, width 10
    (0xED4C, 0xED4E),   # window $29 (message speed, boot menu): row -2 (2026-11-14), width 7
    (0xC4FD, 0xC509),   # return_inline_block: the return address read before the pops (IRQ-safe)
    (0xF0D8, 0xF0D8),   # enter_party_screen: lda #ATT_BANK (the attract mode in kanji)
    (0xF0DD, 0xF0DE),   # its jmp: bank 24's $8000
]


def fourscreen_ranges():
    """Map-canvas step 2: the game routines and tables kanji_build.py
    rewrites in place (FOURSCREEN_REGIONS, checked there by hash)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "kanji_build", Path(__file__).resolve().parent / "kanji_build.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return [(lo, hi) for lo, hi, _ in mod.FOURSCREEN_REGIONS]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rom", type=Path, default=KANJI)
    args = ap.parse_args()
    if not ORIGINAL.exists() or not args.rom.exists():
        print("lint: missing ROM", file=sys.stderr)
        return 2
    data = args.rom.read_bytes()
    if len(data) < 16 + 32 * 0x4000:
        print("lint: ROM is not the 512 KiB kanji target", file=sys.stderr)
        return 2
    original = ORIGINAL.read_bytes()[16 + 15 * 0x4000:16 + 16 * 0x4000]
    # Since the debloat (2026-11-14) the patched fixed bank is bank 31 alone;
    # slot 15 is free (JAM bytes, $02: nothing maps it at $8000).
    slot15 = data[16 + 15 * 0x4000:16 + 16 * 0x4000]
    if slot15 != bytes((0x02,)) * 0x4000:
        print("lint: slot 15 is not free (JAM bytes)", file=sys.stderr)
        return 1
    got = data[16 + 31 * 0x4000:16 + 32 * 0x4000]
    allowed = set()
    patches = PATCHES + fourscreen_ranges()
    for a, b in patches:
        allowed.update(range(a - 0xC000, b - 0xC000 + 1))
    bad = [i for i in range(0x4000) if got[i] != original[i] and i not in allowed]
    if bad:
        print(f"lint: {len(bad)} unexpected bank-15 changes; first at "
              f"${0xC000 + bad[0]:04X}", file=sys.stderr)
        return 1
    import json
    overlay = None
    for bank in json.loads(REPORT.read_text(encoding="utf-8"))["data_banks"]:
        base = 16 + bank * 0x4000 + OVERLAY_OFF
        block = data[base:base + OVERLAY_SIZE]
        if overlay is None:
            overlay = block
        elif block != overlay:
            print(f"lint: bank {bank} overlay differs from the first text bank's",
                  file=sys.stderr)
            return 1
    if data[4] != 32 or (data[6] >> 4) | (data[7] & 0xF0) != 4:
        print("lint: header is not 32 x 16 KiB PRG, mapper 4", file=sys.stderr)
        return 1
    if not data[6] & 0x08:
        print("lint: header lacks four-screen nametables (map-canvas)", file=sys.stderr)
        return 1
    print(f"bank15 lint: OK ({len(patches)} registered patch ranges in bank 31, "
          f"slot 15 free, mapper 4)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
