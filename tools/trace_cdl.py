#!/usr/bin/env python3
"""Trace code with Mesen CDL as an execution-backed seed map."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rom import Rom
from cpu6502 import decode, successors

r = Rom()
cdl_path = sys.argv[1] if len(sys.argv) > 1 else 'out/cdl_original.bin'
cdl = open(cdl_path, 'rb').read()
assert len(cdl) == len(r.prg), (len(cdl), len(r.prg))

BASES = [0x8000]*15 + [0xC000]
KNOWN_ENTRIES = {
    15: [0xFFD8, 0xEE79],
}

def trace_bank(bank):
    base = BASES[bank]
    data = r.bank(bank)
    cdl_bank = cdl[bank*0x4000:(bank+1)*0x4000]
    code_bytes = {i for i, v in enumerate(cdl_bank) if v & 1}
    insn = {}
    bad = set()
    work = []
    # vectors / known entry points
    for a in KNOWN_ENTRIES.get(bank, []):
        work.append(a)
    # CDL sub entries and jump targets
    for i, v in enumerate(cdl_bank):
        if v & 0x08:
            work.append(base + i)
        if v & 0x04:
            work.append(base + i)
    # trace closure
    def run_work():
        while work:
            a = work.pop()
            if a in insn or a in bad:
                continue
            off = a - base
            if off < 0 or off >= len(data) or off not in code_bytes:
                bad.add(a)
                continue
            ins = decode(data, off, base)
            if ins is None or any((off + j) not in code_bytes for j in range(ins.size)):
                bad.add(a)
                continue
            insn[a] = ins
            for s in successors(ins):
                if base <= s < base + len(data):
                    work.append(s)
    run_work()
    # Fill uncovered executed code runs.  Operand bytes are already covered
    # by their instruction, so a run start is normally an instruction start.
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
            a = base + off
            work.append(a)
            before = len(insn)
            run_work()
            if len(insn) != before:
                changed = True
    return insn, bad, code_bytes

for bank in range(16):
    insn, bad, code_bytes = trace_bank(bank)
    cov = sum(i.size for i in insn.values())
    print(f"bank {bank:2d}: cdl_code={len(code_bytes):5d} traced_insns={len(insn):5d} traced_bytes={cov:5d} bad={len(bad)}")
    if bad:
        print("   bad:", " ".join(f"${x:04X}" for x in sorted(bad)[:12]))
