#!/usr/bin/env python3
"""Offline check for tools/lua/field_kana_check.lua dumps.

Every lower tile referenced by the command-menu box ($6D/$6E top edge) must
still have the bank-9 kana glyph.  A tile holding a kanji quadrant means a
message leaked its CHR into the menu (D1/D2).
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import qa_sweep as qs  # noqa: E402

ORIGINAL = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
CAPTURE = ROOT / "out" / "test" / "fk"


def font_rows() -> bytes:
    rom = ORIGINAL.read_bytes()
    return rom[16 + 9 * 0x4000 + 0x3A00:16 + 9 * 0x4000 + 0x3E00]


def main() -> int:
    font = font_rows()
    dumps = sorted(CAPTURE.glob("fk_*_ppu.bin"))
    if not dumps:
        print(f"no dumps in {CAPTURE}", file=sys.stderr)
        return 2
    failures = 0
    checked = 0
    for path in dumps:
        frame = path.stem.split("_")[1]
        chr_path = None
        # field_kana_check.lua only dumps PPU and PNG; capture CHR from the
        # matching screenshot is impossible, so this tool expects a variant
        # that writes fk_NNNN_chr.bin (see tools/lua/field_kana_check.lua).
        chr_path = CAPTURE / f"fk_{frame}_chr.bin"
        if not chr_path.exists():
            continue
        ppu = path.read_bytes()
        chr_data = chr_path.read_bytes()
        ram_path = CAPTURE / f"fk_{frame}_ram.bin"
        ram = ram_path.read_bytes() if ram_path.exists() else b""
        base = 0x1000 if (ram and (ram[0xFF] & 0x10)) else 0x0000
        checked += 1
        for nt in (ppu[0x2000:0x2400], ppu[0x2400:0x2800]):
            for y in range(30):
                for x in range(25):
                    if nt[y * 32 + x] != 0x6D or nt[y * 32 + x + 7] != 0x6E:
                        continue
                    for dx in range(8):
                        t = nt[y * 32 + x + dx]
                        if t >= 0x80 or t in qs.FRAME_TILES or t == 0x0A:
                            continue
                        cur = chr_data[base + t * 16:base + (t + 1) * 16]
                        ref = font[t * 8:(t + 1) * 8] + b"\x00" * 8
                        if cur != ref:
                            print(f"fk_{frame}: menu tile ${t:02X} corrupted "
                                  f"at {x + dx},{y}")
                            failures += 1
    print(f"checked {checked} dumps, {failures} corrupted menu tiles")
    return 0 if failures == 0 and checked else 1


if __name__ == "__main__":
    raise SystemExit(main())
