#!/usr/bin/env python3
"""List absolute-operand references (JSR/JMP/LDA abs,x ...) into address
ranges, across all 16 banks of the original ROM.  Raw byte scan: data can
show up as false positives; every hit needs a look.

Usage: python -I tools/ref_scan.py LO-HI [LO-HI ...]   (hex, inclusive)
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROM = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
# 6502 opcodes with a 16-bit operand (abs, abs,x, abs,y, ind, jsr)
ABS = {0x0D,0x0E,0x19,0x1D,0x1E,0x20,0x2C,0x2D,0x2E,0x39,0x3D,0x3E,0x4C,0x4D,0x4E,
       0x59,0x5D,0x5E,0x6C,0x6D,0x6E,0x79,0x7D,0x7E,0x8C,0x8D,0x8E,0x99,0x9D,0xAC,
       0xAD,0xAE,0xB9,0xBC,0xBD,0xBE,0xCC,0xCD,0xCE,0xD9,0xDD,0xDE,0xEC,0xED,0xEE,
       0xF9,0xFD,0xFE}

def main() -> int:
    ranges = []
    for arg in sys.argv[1:]:
        lo, hi = (int(x, 16) for x in arg.split("-"))
        ranges.append((lo, hi))
    prg = ROM.read_bytes()[16:]
    for bank in range(16):
        data = prg[bank * 0x4000:(bank + 1) * 0x4000]
        base = 0xC000 if bank == 15 else 0x8000
        for i in range(len(data) - 2):
            if data[i] not in ABS:
                continue
            t = data[i + 1] | (data[i + 2] << 8)
            for lo, hi in ranges:
                if lo <= t <= hi:
                    print(f"bank {bank:2d} ${base + i:04X}: {data[i]:02X} {data[i+1]:02X} {data[i+2]:02X} -> ${t:04X}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
