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
    (0xC611, 0xC676),   # switcher + far head + band stub + reset hook
    (0xD190, 0xD192),   # jsr jump_exit_13 (<JUMP>)
    (0xD198, 0xD19A),   # jsr jump_exit_14 (<JUMP>)
    (0xD1FA, 0xD1FC),   # jmp exit_clear
    (0xD28E, 0xD290),   # jmp text_dispatch
    (0xD2C7, 0xD2C9),   # jsr ctrl_store
    (0xDBE7, 0xDBEA),   # jsr cell_check + bcc
    (0xD420, 0xD422),   # jmp redraw_high
    (0xEEDD, 0xEEDF),   # jsr band_stub
    (0xF022, 0xF022),   # reset CHR reg 1 = page 1
    (0xF036, 0xF039),   # jsr reset_extra + nop
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
    print(f"bank15 lint: OK ({len(PATCHES)} registered patch ranges, "
          f"bank31 == bank15)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
