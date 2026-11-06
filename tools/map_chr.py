#!/usr/bin/env python3
"""Map dumped CHR RAM pages back to their PRG source offsets.

The game uses CHR RAM and uploads raw 2bpp tiles from PRG.  This tool finds,
for each 256-byte CHR page, the PRG offset that best explains its non-zero
64-byte windows.  It is a diagnostic for building editable tile resources.
"""
from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROM = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"


def main() -> int:
    prg = ROM.read_bytes()[16:]
    files = [Path(p) for p in sys.argv[1:]] or [ROOT / "out" / "dialogue" / "chr.bin"]
    for path in files:
        data = path.read_bytes()
        print(f"== {path.name} ({len(data)} bytes)")
        for page in range(0, len(data), 0x100):
            chunk = data[page:page + 0x100]
            votes = Counter()
            for off in range(0, 0x100, 0x40):
                needle = chunk[off:off + 0x40]
                if not any(needle):
                    continue
                pos = prg.find(needle)
                if pos >= 0:
                    votes[pos - off] += 1
            if votes:
                base, n = votes.most_common(1)[0]
                bank = base // 0x4000
                cpu = (0xC000 if bank == 15 else 0x8000) + (base % 0x4000)
                print(f"  chr ${page:04X}: {n}/4 windows -> prg ${base:06X} bank {bank:02d} ${cpu:04X}")
            else:
                print(f"  chr ${page:04X}: no raw PRG match (generated/compressed?)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
