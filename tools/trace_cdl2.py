#!/usr/bin/env python3
"""Trace code with CDL seeds, then follow unexecuted branches statically."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rom import Rom
from cpu6502 import decode, successors

r = Rom()
cdl_path = sys.argv[1] if len(sys.argv) > 1 else 'out/cdl_combined.bin'
cdl = open(cdl_path, 'rb').read()
assert len(cdl) == len(r.prg)
BASES = [0x8000]*15 + [0xC000]
KNOWN_ENTRIES = {15: [0xFFD8, 0xEE79]}

def trace_bank(bank):
    base = BASES[bank]
    data = r.bank(bank)
    cdl_bank = cdl[bank*0x4000:(bank+1)*0x4000]
    code_bytes = {i for i, v in enumerate(cdl_bank) if v & 1}
    data_only = {i for i, v in enumerate(cdl_bank) if (v & 2) and not (v & 1)}
    insn = {}
    bad = set()
    work = []
    for a in KNOWN_ENTRIES.get(bank, []):
        work.append(a)
    for i, v in enumerate(cdl_bank):
        if v & 0x0C:
            work.append(base + i)
    def ok(off, size):
        return off >= 0 and off + size <= len(data) and not any((off+j) in data_only for j in range(size))
    def run_work():
        while work:
            a = work.pop()
            if a in insn or a in bad:
                continue
            off = a - base
            ins = decode(data, off, base) if 0 <= off < len(data) else None
            if ins is None or not ok(off, ins.size):
                bad.add(a)
                continue
            insn[a] = ins
            for s in successors(ins):
                if base <= s < base + len(data):
                    work.append(s)
    run_work()
    # Fill uncovered executed code runs.
    changed = True
    while changed:
        changed = False
        covered = set()
        for a, ins in insn.items():
            for j in range(ins.size):
                covered.add(a + j - base)
        i = 0
        starts = []
        while i < len(data):
            if i in code_bytes and i not in covered:
                starts.append(i)
                while i < len(data) and i in code_bytes and i not in covered:
                    i += 1
            else:
                i += 1
        for off in starts:
            before = len(insn)
            work.append(base + off)
            run_work()
            if len(insn) != before:
                changed = True
    return insn, bad, code_bytes

for bank in range(16):
    insn, bad, code_bytes = trace_bank(bank)
    cov = sum(i.size for i in insn.values())
    unverified = sum(1 for a, i in insn.items() if not any((a - BASES[bank] + j) in code_bytes for j in range(i.size)))
    print(f"bank {bank:2d}: cdl_code={len(code_bytes):5d} insns={len(insn):5d} bytes={cov:5d} unverified_insns={unverified:4d} bad={len(bad)}")
    if bad:
        print("   bad:", " ".join(f"${x:04X}" for x in sorted(bad)[:12]))
