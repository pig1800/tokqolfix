#!/usr/bin/env python3
"""Fail if the kanji target changes the fixed bank outside registered sites.

The fixed bank (bank 15) must keep every original byte and address except the
registered patch ranges below.  Bank 31 must be a byte-identical copy of
patched bank 15 so code can run with either SUROM outer bit selected.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ORIGINAL = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
KANJI = ROOT / "decomp" / "build" / "rom_kanji.nes"
TEXT_BANKS = range(18, 23)
OVERLAY_OFF = 0x3800
OVERLAY_SIZE = 0x800

PATCHES = [
    (0xC469, 0xC469),   # mmc1_init control: 4K CHR mode
    (0xC4B7, 0xC4B9),   # jmp SUROM switcher
    (0xC48C, 0xC48E),   # set_bank_lock: jsr SUROM switcher
    (0xC44F, 0xC44F),   # clear_oam_shadow: ldx #$04 (slot 0 is the NMI's)
    (0xC5A6, 0xC6D1),   # load_text_graphics (tables moved), switcher, call_hack, block hook
    (0xC4BA, 0xC4CA),   # NMI EF08 hook (dead write_prg_bank body)
    (0xC343, 0xC345),   # jmp c343_hook
    (0xD28E, 0xD290),   # jmp text_dispatch
    (0xD291, 0xD2B6),   # NMI epilogue hook (dead original $EF-$F7 dispatch)
    (0xD2C7, 0xD2C9),   # jsr ctrl_store
    (0xD1C8, 0xD1CA),   # jsr page_flip (kanji page flip after the <PAGE> wait)
    (0xDBED, 0xDBEE),   # text_render_cell: jmp render_ctl (battle pool tiles)
    (0xEF0B, 0xEF0F),   # jmp ef08_gate + nop nop
    (0xEF31, 0xEF33),   # jmp ef31_gate
    (0xF00C, 0xF039),   # reset CHR registers + hack RAM clear (rewritten)
    (0xFFE0, 0xFFEF),   # block-writer entry, overlay frame wait (padding)
]


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
    got = data[16 + 15 * 0x4000:16 + 16 * 0x4000]
    bank31 = data[16 + 31 * 0x4000:16 + 32 * 0x4000]
    if got != bank31:
        bad = next((i for i in range(0x4000) if got[i] != bank31[i]), 0)
        print(f"lint: bank 31 differs from bank 15 at ${0xC000 + bad:04X}",
              file=sys.stderr)
        return 1
    allowed = set()
    for a, b in PATCHES:
        allowed.update(range(a - 0xC000, b - 0xC000 + 1))
    bad = [i for i in range(0x4000) if got[i] != original[i] and i not in allowed]
    if bad:
        print(f"lint: {len(bad)} unexpected bank-15 changes; first at "
              f"${0xC000 + bad[0]:04X}", file=sys.stderr)
        return 1
    overlay = None
    for bank in TEXT_BANKS:
        base = 16 + bank * 0x4000 + OVERLAY_OFF
        block = data[base:base + OVERLAY_SIZE]
        if overlay is None:
            overlay = block
        elif block != overlay:
            print(f"lint: bank {bank} overlay differs from bank 18",
                  file=sys.stderr)
            return 1
    # Outer-half marker read by surom_write_prg_bank (revision 15): $BFFF
    # has bit 7 set in every lower-half bank and clear in banks 16-30.
    for bank in range(31):
        mark = data[16 + bank * 0x4000 + 0x3FFF]
        if bool(mark & 0x80) != (bank < 16):
            print(f"lint: bank {bank} $BFFF = ${mark:02X} breaks the outer-half "
                  "marker (bit 7 set only in banks 0-15)", file=sys.stderr)
            return 1
    print(f"bank15 lint: OK ({len(PATCHES)} registered patch ranges, "
          f"bank31 == bank15, outer marker)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
