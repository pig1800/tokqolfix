#!/usr/bin/env python3
"""Prototype recursive tracer: report coverage before generating source."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rom import Rom
from cpu6502 import decode, successors

r = Rom()

BANKS = {
    7:  (0x8000, [(0x9400, 0x9E82)], [(0x9411, "bank7_entry")]),
    8:  (0x8000, [(0x8000, 0x8A50)], [(0x8000, "sound_entry0"), (0x8003, "sound_entry3")]),
    13: (0x8000, [(0x8800, 0x9000), (0x9C00, 0x9FDA), (0xA075, 0xB700)],
         [(0x8800, "bank13_8800"), (0x9C00, "bank13_9C00"), (0xA075, "bank13_A075")]),
    14: (0x8000, [(0x8000, 0xC000)], [(0x8000, "bank14_entry")]),
    15: (0xC000, [(0xC000, 0xFF00)], [(0xFFD8, "reset"), (0xEE79, "nmi")]),
}


def trace_bank(bank, base, ranges, seeds, scan=True):
    data = r.bank(bank)
    lo = base
    hi = base + len(data)
    allowed = [(max(a, lo), min(b, hi)) for a, b in ranges]
    def in_range(a):
        return any(x <= a < y for x, y in allowed)
    insn = {}
    bad = set()
    work = [a for a, _ in seeds]
    if scan:
        # Single broad sweep for call/jump opcodes.  False positives are
        # harmless as long as they land on an invalid opcode or outside a
        # range; they are reported as "bad" for manual review.
        for a, b in allowed:
            for rel in range(a - base, b - base):
                if data[rel] in (0x20, 0x4C):
                    ins = decode(data, rel, base)
                    if ins and ins.value is not None and in_range(ins.value):
                        work.append(ins.value)
    while work:
        a = work.pop()
        if a in insn or a in bad or not in_range(a):
            continue
        ins = decode(data, a - base, base)
        if ins is None:
            bad.add(a)
            continue
        insn[a] = ins
        for s in successors(ins):
            if in_range(s):
                work.append(s)
    return insn, bad, allowed


for bank, (base, ranges, seeds) in BANKS.items():
    insn, bad, allowed = trace_bank(bank, base, ranges, seeds, scan=False)
    cov = sum(i.size for i in insn.values())
    total = sum(b - a for a, b in allowed)
    used = sorted((a, a + i.size, i.mnemonic) for a, i in insn.items())
    gaps = []
    cur = allowed[0][0]
    for a, e, _ in used:
        if a > cur:
            gaps.append((cur, a, a - cur))
        cur = max(cur, e)
    for _, b in allowed:
        if cur < b:
            gaps.append((cur, b, b - cur))
    gaps.sort(key=lambda x: -x[2])
    print(f"bank {bank:2d}: insns={len(insn):5d} bytes={cov:5d}/{total:5d} ({100*cov/total:5.1f}%) bad={len(bad)}")
    if bad:
        print("   bad:", " ".join(f"${x:04X}" for x in sorted(bad)[:20]))
    if gaps:
        print("   gaps:", " ".join(f"${a:04X}-${b:04X}({n})" for a, b, n in gaps[:12]))
