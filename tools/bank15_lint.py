#!/usr/bin/env python3
"""Fail if the kanji target changes bank 15 outside the registered patches.

The fixed bank must keep every original byte and address except:
  $C4B7-$C4B9  JMP to the SUROM switcher
  $C611-$C639  SUROM switcher (inside an audited unused data gap)
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ORIGINAL = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
KANJI = ROOT / "decomp" / "build" / "rom_kanji.nes"

PATCHES = [
    (0xC4B7, 0xC4B9),
    (0xC611, 0xC639),
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rom", type=Path, default=KANJI)
    args = ap.parse_args()
    if not ORIGINAL.exists() or not args.rom.exists():
        print("lint: missing ROM", file=sys.stderr)
        return 2
    original = ORIGINAL.read_bytes()[16 + 15 * 0x4000:16 + 16 * 0x4000]
    got = args.rom.read_bytes()[16 + 15 * 0x4000:16 + 16 * 0x4000]
    if len(got) != 0x4000:
        print("lint: bank 15 out of range", file=sys.stderr)
        return 2
    allowed = set()
    for a, b in PATCHES:
        allowed.update(range(a - 0xC000, b - 0xC000 + 1))
    bad = [i for i in range(0x4000) if got[i] != original[i] and i not in allowed]
    if bad:
        print(f"lint: {len(bad)} unexpected bank-15 changes; first at "
              f"${0xC000 + bad[0]:04X}", file=sys.stderr)
        return 1
    print(f"bank15 lint: OK ({len(PATCHES)} registered patch ranges)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
