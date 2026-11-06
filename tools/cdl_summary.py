#!/usr/bin/env python3
"""Summarize a Mesen CDL dump (raw one-byte-per-PRG-byte)."""
import sys, os

path = sys.argv[1] if len(sys.argv) > 1 else 'out/cdlprobe/cdl.bin'
cdl = open(path, 'rb').read()
print(f"{path}: {len(cdl)} bytes")
for bank in range(16):
    d = cdl[bank*0x4000:(bank+1)*0x4000]
    code = [i for i, x in enumerate(d) if x & 1]
    data = [i for i, x in enumerate(d) if x & 2]
    jmp = [i for i, x in enumerate(d) if x & 4]
    sub = [i for i, x in enumerate(d) if x & 8]
    if code or data:
        def ranges(idxs):
            out = []
            start = prev = None
            for i in idxs:
                if start is None:
                    start = prev = i
                elif i == prev + 1:
                    prev = i
                else:
                    out.append((start, prev))
                    start = prev = i
            if start is not None:
                out.append((start, prev))
            return out
        print(f"bank {bank:2d}: code={len(code):5d} data={len(data):5d} jmp={len(jmp):4d} sub={len(sub):4d}")
        cr = ranges(code)
        print("  code ranges:", " ".join(f"${a:04X}-${b:04X}" for a, b in cr[:12]) + (" ..." if len(cr) > 12 else ""))
        if sub:
            print("  sub entries:", " ".join(f"${i:04X}" for i in sub[:30]) + (" ..." if len(sub) > 30 else ""))
