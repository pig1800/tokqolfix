#!/usr/bin/env python3
"""Search PRG for byte patterns and report bank/CPU address."""
import sys, argparse
from rom import Rom

def find(r, pattern, bank=None, maxhits=200):
    pat = bytes.fromhex(pattern.replace(' ',''))
    hits = []
    banks = [bank] if bank is not None else range(r.prg_banks)
    for b in banks:
        data = r.bank(b)
        i = 0
        while True:
            i = data.find(pat, i)
            if i < 0: break
            hits.append((b, i, 0x8000 + i if b < r.prg_banks-1 else 0xC000 + i))
            i += 1
            if len(hits) >= maxhits: return hits
    return hits

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('pattern')
    ap.add_argument('--bank', type=lambda s: int(s,0), default=None)
    ap.add_argument('--max', type=int, default=200)
    a = ap.parse_args()
    r = Rom()
    hits = find(r, a.pattern, a.bank, a.max)
    for b,i,a_ in hits:
        print(f"bank {b:2d} off ${i:04X} cpu ${a_:04X}")

if __name__ == '__main__':
    main()
