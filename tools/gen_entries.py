#!/usr/bin/env python3
"""Emit candidate entry addresses for a Ghidra seeding pass."""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decompile import BASES, DEFAULT_CDL, KNOWN_ENTRIES, load_cdl, trace_bank
from rom import Rom


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("bank", type=lambda s: int(s, 0))
    ap.add_argument("--cdl", default=str(DEFAULT_CDL))
    ap.add_argument("-o", "--out")
    args = ap.parse_args()
    r = Rom()
    cdl = load_cdl([args.cdl])
    bank = args.bank
    insn, bad, code_bytes, data_only = trace_bank(r, bank, cdl)
    base = BASES[bank]
    entries = set()
    for a, i in insn.items():
        if i.mnemonic == "jsr" and i.mode == "abs" and base <= i.value < base + 0x4000:
            if i.value in insn:
                entries.add(i.value)
    for x in KNOWN_ENTRIES.get(bank, []):
        if x in insn:
            entries.add(x)
    # CDL subroutine-entry bits are execution-backed function starts.
    cdl_bank = cdl[bank * 0x4000:(bank + 1) * 0x4000]
    for i, v in enumerate(cdl_bank):
        if (v & 0x08) and (base + i) in insn:
            entries.add(base + i)
    if bank == 15:
        entries.add(0xC000)
    entries = sorted(entries)
    text = "\n".join(f"0x{x:04X}" for x in entries) + "\n"
    if args.out:
        Path(args.out).write_text(text, encoding="utf-8")
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
