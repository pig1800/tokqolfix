#!/usr/bin/env python3
"""Summary information about each 16 KB PRG bank."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rom import Rom

r = Rom()
print(f"PRG banks={r.prg_banks}, size={len(r.prg)}")
for b in range(r.prg_banks):
    d = r.bank(b)
    nz = sum(1 for x in d if x)
    # longest zero run
    best = cur = 0
    best_at = cur_at = 0
    for i, x in enumerate(d):
        if x == 0:
            if cur == 0:
                cur_at = i
            cur += 1
            if cur > best:
                best = cur
                best_at = cur_at
        else:
            cur = 0
    first = next((i for i, x in enumerate(d) if x), None)
    last = next((len(d) - 1 - i for i, x in enumerate(reversed(d)) if x), None)
    print(f"bank {b:2d}: nonzero={nz:5d}/{len(d)} first=${first:04X} last=${last:04X} longest_zero={best} at ${best_at:04X}")

print("\nEntry bytes of each bank:")
for b in range(r.prg_banks):
    d = r.bank(b)
    print(f"bank {b:2d}: " + " ".join(f"{x:02X}" for x in d[:16]))
