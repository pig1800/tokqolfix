#!/usr/bin/env python3
"""Build a routine-level analysis database for the traced 6502 code.

The output is JSON (and optionally a text listing) used by the source
generator and by the manual naming pass.  Function bodies are found by
following intra-bank control flow from JSR/known entry points, stopping at
RTS/RTI/BRK, at a JMP to another known entry, or when the instruction stream
leaves the bank.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decompile import BASES, DEFAULT_CDL, load_cdl, trace_bank
from rom import Rom

MEM_OPS = {
    "lda", "ldx", "ldy", "sta", "stx", "sty", "bit", "asl", "lsr", "rol", "ror",
    "inc", "dec", "adc", "sbc", "and", "ora", "eor", "cmp", "cpx", "cpy",
}
WRITE_OPS = {"sta", "stx", "sty", "asl", "lsr", "rol", "ror", "inc", "dec"}


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
    return m


def collect_func(insn, start, starts, base, end):
    """Follow control flow from start without entering JSR callees."""
    body = {}
    work = [start]
    seen_blocks = set()
    while work:
        a = work.pop()
        while base <= a < end and a in insn and a not in body:
            ins = insn[a]
            body[a] = ins
            nxt = a + ins.size
            if ins.mnemonic == "jsr":
                # Do not descend; record edge only.
                a = nxt
                continue
            if ins.mnemonic in ("rts", "rti", "brk"):
                break
            if ins.mnemonic == "jmp":
                if ins.mode == "abs":
                    t = ins.value
                    if t in starts and t != start:
                        # tail call or shared dispatch block: stop body here
                        break
                    a = t
                    continue
                break
            if ins.mnemonic in ("bpl", "bmi", "bvc", "bvs", "bcc", "bcs", "bne", "beq"):
                if ins.value in insn and base <= ins.value < end:
                    if ins.value in starts and ins.value != start:
                        # shared tail block; treat as tail target, not body
                        pass
                    else:
                        work.append(ins.value)
                a = nxt
                continue
            a = nxt
        # avoid runaway loops
    return body


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdl", default=str(DEFAULT_CDL))
    ap.add_argument("--json", default=str(Path("out") / "functions.json"))
    ap.add_argument("--bank", type=lambda s: int(s, 0), default=None)
    args = ap.parse_args()
    r = Rom()
    cdl = load_cdl([args.cdl])
    banks = [args.bank] if args.bank is not None else list(range(16))
    out = {}
    for bank in banks:
        insn, bad, code_bytes, data_only = trace_bank(r, bank, cdl)
        base = BASES[bank]
        end = base + 0x4000
        starts = set()
        # JSR targets are the primary function starts.
        for a, i in insn.items():
            if i.mnemonic == "jsr" and i.mode == "abs" and base <= i.value < end:
                starts.add(i.value)
        # Known entries and CDL sub entries.
        from decompile import KNOWN_ENTRIES
        starts.update(x for x in KNOWN_ENTRIES.get(bank, []) if x in insn)
        if bank == 15:
            starts.add(0xC000)
        starts = {a for a in starts if a in insn}
        callers = defaultdict(list)
        for a, i in insn.items():
            if i.mnemonic == "jsr" and i.mode == "abs" and base <= i.value < end:
                callers[i.value].append(a)
        funcs = []
        for s in sorted(starts):
            body = collect_func(insn, s, starts, base, end)
            if not body:
                continue
            size = sum(i.size for i in body.values())
            calls = sorted({i.value for i in body.values() if i.mnemonic == "jsr" and i.mode == "abs"})
            tail = sorted({i.value for i in body.values() if i.mnemonic == "jmp" and i.mode == "abs"})
            reads = defaultdict(int)
            writes = defaultdict(int)
            for i in body.values():
                if i.mnemonic in MEM_OPS and i.mode in ("zp", "zpx", "zpy", "abs", "abx", "aby"):
                    target = i.value
                    # Ignore absolute operands that are clearly code/data in this bank.
                    if base <= target < end and i.mode in ("abs", "abx", "aby"):
                        continue
                    (writes if i.mnemonic in WRITE_OPS else reads)[target] += 1
            funcs.append({
                "start": s,
                "end": max(a + i.size for a, i in body.items()),
                "entry": f"${s:04X}",
                "size": size,
                "instructions": [{"addr": a, "text": fmt(i), "bytes": i.raw.hex()} for a, i in sorted(body.items())],
                "callers": callers.get(s, []),
                "calls": calls,
                "tail_calls": tail,
                "reads": dict(sorted(reads.items())),
                "writes": dict(sorted(writes.items())),
            })
        out[bank] = {"base": base, "functions": funcs}
        print(f"bank {bank:02d}: {len(funcs)} functions, {sum(f['size'] for f in funcs)} bytes")
    Path(args.json).parent.mkdir(parents=True, exist_ok=True)
    Path(args.json).write_text(json.dumps(out, indent=1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
