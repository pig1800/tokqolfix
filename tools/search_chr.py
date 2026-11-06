#!/usr/bin/env python3
"""Search dumped CHR RAM images for matching byte runs inside the PRG ROM."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROM = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"


def main() -> int:
    rom = ROM.read_bytes()
    prg = rom[16:]
    files = [Path(p) for p in sys.argv[1:]]
    if not files:
        files = [ROOT / "out" / "dialogue" / "chr.bin"]
    for path in files:
        data = path.read_bytes()
        print(f"== {path} ({len(data)} bytes)")
        # Longest common substring is too slow; test 64-byte aligned windows.
        best = (0, None, None)
        for step in (16, 32, 64, 128):
            hits = []
            for off in range(0, len(data) - step + 1, step):
                needle = data[off:off + step]
                pos = prg.find(needle)
                if pos >= 0:
                    hits.append((off, pos))
            print(f"  {step:3d}-byte aligned windows: {len(hits)} hits")
            if hits and step > best[0]:
                best = (step, hits[0][0], hits[0][1])
            for off, pos in hits[:8]:
                print(f"    chr ${off:04X} -> prg ${pos:06X} (bank {pos // 0x4000:02d}, ${0x8000 + pos % 0x4000:04X})")
        # Find the longest exact run by extending every 16-byte match.
        best_run = 0
        best_info = None
        for off in range(0, len(data) - 16 + 1, 16):
            pos = prg.find(data[off:off + 16])
            if pos < 0:
                continue
            # extend forward
            n = 16
            while off + n < len(data) and pos + n < len(prg) and data[off + n] == prg[pos + n]:
                n += 1
            if n > best_run:
                best_run = n
                best_info = (off, pos)
        print(f"  longest exact run: {best_run} bytes at {best_info}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
