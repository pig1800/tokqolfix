#!/usr/bin/env python3
"""Report candidate routine entry points from the CDL-backed trace.

This is an analysis helper, not part of the build.  It prints JSR/JMP targets
that fall inside traced code, their caller count, and a compact disassembly of
the first instructions so routines can be named.
"""
from __future__ import annotations

import argparse
import os
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decompile import BASES, DEFAULT_CDL, load_cdl, trace_bank
from rom import Rom


def fmt(ins) -> str:
    m, mode, v = ins.mnemonic, ins.mode, ins.value
    if mode in ("imp", "acc"):
        return m + (" a" if mode == "acc" else "")
    if mode == "imm":
        return f"{m} #${v:02X}"
    if mode in ("zp", "zpx", "zpy"):
        return f"{m} ${v:02X}" + {"zpx": ",x", "zpy": ",y", "zp": ""}[mode]
    if mode in ("abs", "abx", "aby"):
        return f"{m} ${v:04X}" + {"abx": ",x", "aby": ",y", "abs": ""}[mode]
    if mode == "rel":
        return f"{m} ${v:04X}"
    if mode == "ind":
        return f"{m} (${v:04X})"
    if mode == "izx":
        return f"{m} (${v:02X},x)"
    if mode == "izy":
        return f"{m} (${v:02X}),y"
    return f"{m} ?"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("bank", type=lambda s: int(s, 0))
    ap.add_argument("--cdl", default=str(DEFAULT_CDL))
    ap.add_argument("--max", type=int, default=8)
    args = ap.parse_args()
    r = Rom()
    cdl = load_cdl([args.cdl])
    bank = args.bank
    insn, bad, code_bytes, data_only = trace_bank(r, bank, cdl)
    base = BASES[bank]

    callers = defaultdict(list)
    for addr, ins in insn.items():
        if ins.mnemonic in ("jsr", "jmp") and ins.mode == "abs":
            t = ins.value
            if base <= t < base + 0x4000:
                callers[t].append((addr, ins.mnemonic))
    starts = sorted(t for t in callers if t in insn)
    print(f"bank {bank:02d}: {len(starts)} candidate targets")
    for t in starts:
        cs = callers[t]
        print(f"\n${t:04X}  callers={len(cs)}  {', '.join(f'${a:04X}{m[0]}' for a,m in cs[:8])}")
        # linear display from entry, bounded by 12 instructions / 48 bytes
        a = t
        n = 0
        while a in insn and n < args.max and a < base + 0x4000:
            ins = insn[a]
            print(f"  ${a:04X}: {fmt(ins)}")
            if ins.mnemonic in ("rts", "rti", "brk"):
                break
            a += ins.size
            n += 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
