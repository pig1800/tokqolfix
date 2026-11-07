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
OVERLAY_BANK = ROOT / "decomp" / "build" / "kanji" / "bank24.bin"

PATCHES = [
    (0xC4B7, 0xC4B9),   # jmp SUROM switcher
    (0xC611, 0xC675),   # switcher + far stub + NMI guards
    (0xCC02, 0xCC04),   # jsr kana_prepare (menu text)
    (0xD1FA, 0xD1FC),   # jmp restore_exit
    (0xD28E, 0xD290),   # jmp text_dispatch
    (0xD2BB, 0xD2BD),   # jsr kana_prepare
    (0xD2C7, 0xD2C9),   # jsr ctrl_store
    (0xD32B, 0xD32D),   # jsr kana_prepare (word handler)
    (0xD388, 0xD38A),   # jsr redraw_hook
    (0xDBE7, 0xDBE9),   # jsr cell_check
    (0xDBEA, 0xDBEA),   # bcc (tiles $00-$F9)
    (0xD4C0, 0xD4C2),   # jsr kana_prepare (name handler)
    (0xD57D, 0xD57F),   # jsr kana_prepare (item name)
    (0xD582, 0xD584),   # jsr kana_prepare (item name)
    (0xD5C0, 0xD5C2),   # jsr kana_prepare (item name)
    (0xEE7F, 0xEE81),   # jmp nmi_entry_guard
    (0xEECB, 0xEECD),   # jsr nmi_palette_guard
]

FAR_STUB = bytes((0xA9, 0x0D, 0x20, 0x82, 0xC4, 0x4C, 0x17, 0x83))


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
    off = 0xC63A - 0xC000
    if got[off:off + len(FAR_STUB)] != FAR_STUB:
        print("lint: far stub at $C63A has unexpected bytes", file=sys.stderr)
        return 1
    if OVERLAY_BANK.exists():
        overlay = OVERLAY_BANK.read_bytes()
        if overlay[0:2] != b"KO":
            print("lint: overlay bank has no signature", file=sys.stderr)
            return 1
    print(f"bank15 lint: OK ({len(PATCHES)} registered patch ranges, "
          f"bank31 == bank15)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
