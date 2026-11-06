#!/usr/bin/env python3
"""Find dense little-endian pointer tables that point into code ranges."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rom import Rom

r = Rom()
BASES = [0x8000]*15 + [0xC000]

def ranges_of(bank, words, minrun=4):
    runs = []
    n = len(words)
    i = 0
    while i + minrun <= n:
        # try run starting at i
        j = i
        vals = []
        last = None
        while j < n:
            w = words[j]
            if w is None:
                break
            vals.append(w)
            j += 1
        if len(vals) >= minrun:
            runs.append((i, j, vals))
        i = max(j, i + 1)
    return runs

for bank in [13, 14, 15, 7, 8]:
    data = r.bank(bank)
    base = BASES[bank]
    # Words that point into this bank or the fixed bank.
    good = []
    for off in range(0, len(data) - 1, 2):
        w = data[off] | (data[off + 1] << 8)
        ok = (base <= w < base + 0x4000) or (0xC000 <= w < 0x10000)
        good.append(w if ok else None)
    runs = ranges_of(bank, good, 4)
    # Keep reasonably dense runs and shorten them to contiguous good words.
    print(f"bank {bank}: {len(runs)} candidate runs")
    for start, end, vals in runs[:20]:
        print(f"  ${base+start*2:04X}: " + " ".join(f"${w:04X}" for w in vals[:16]) + (" ..." if len(vals) > 16 else ""))
