#!/usr/bin/env python3
"""Fail if the kanji target changes the fixed bank outside registered sites.

The fixed bank (bank 15) must keep every original byte and address except the
registered patch ranges below.  Bank 31 (the MMC3 fixed bank at
$C000-$FFFF) must be a byte-identical copy of patched bank 15.
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
    (0xC460, 0xC47D),   # dead mmc1_reset/mmc1_init: render_ctl, chr1_scene
    (0xC486, 0xC488),   # set_bank_lock: jmp main_prg (MMC3)
    (0xC4AA, 0xC4AC),   # restore_bank_after_nmi: jmp nmi_prg (MMC3)
    (0xC44F, 0xC450),   # clear_oam_shadow: ldx #$04 / bne (slot 0 is the NMI's)
    (0xC5A6, 0xC6D1),   # load_text_graphics (tables moved), MMC3 switches, call_hack, block hook
    (0xC4BA, 0xC4CA),   # NMI EF08 hook (dead write_prg_bank body)
    (0xC343, 0xC345),   # jmp c343_hook
    (0xD28E, 0xD290),   # jmp text_dispatch
    (0xD291, 0xD2B6),   # NMI epilogue hook (dead original $EF-$F7 dispatch)
    (0xD2C7, 0xD2C9),   # jsr ctrl_store
    (0xD1C8, 0xD1CA),   # jsr page_flip (kanji page flip after the <PAGE> wait)
    (0xDBED, 0xDBEE),   # text_render_cell: jmp render_ctl (battle pool tiles)
    (0xD416, 0xD426),   # text_redraw_lines: keep cells below $FA (battle pool scroll)
    (0xEF0B, 0xEF0F),   # jmp ef08_gate + nop nop
    (0xEF31, 0xEF33),   # jmp ef31_gate
    (0xF004, 0xF039),   # reset: MMC3 registers + hack RAM clear (rewritten)
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
    if data[4] != 32 or (data[6] >> 4) | (data[7] & 0xF0) != 4:
        print("lint: header is not 32 x 16 KiB PRG, mapper 4", file=sys.stderr)
        return 1
    print(f"bank15 lint: OK ({len(PATCHES)} registered patch ranges, "
          f"bank31 == bank15, mapper 4)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
