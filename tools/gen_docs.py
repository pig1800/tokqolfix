#!/usr/bin/env python3
"""Generate decomp/FUNCTIONS.md and decomp/BANKS.md from the live analysis."""
from __future__ import annotations

import os
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rom import Rom
from trace6502 import BASES, DEFAULT_CDL, load_cdl, trace_bank
from symbols import DOCS, NAMES
from decompile import build_labels, find_inline_blocks
from func_analyze import collect_func

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "decomp"


def main() -> int:
    r = Rom()
    cdl = load_cdl([str(DEFAULT_CDL)])
    traces = {b: trace_bank(r, b, cdl) for b in range(16)}
    inline = {}
    for b in range(16):
        inline[b] = find_inline_blocks(traces[b][0], b)
        insn = traces[b][0]
        for start, block in inline[b].items():
            if any(a in insn for a, _ in block):
                continue
            for a, i in block:
                insn[a] = i

    all_labels = {b: build_labels(b, traces[b][0], cdl) for b in range(16)}
    callers = defaultdict(list)
    jsr_targets = defaultdict(set)
    for b in range(16):
        for a, i in traces[b][0].items():
            if i.mnemonic == "jsr" and i.mode == "abs":
                callers[i.value].append(a)
                if BASES[b] <= i.value < BASES[b] + 0x4000:
                    jsr_targets[b].add(i.value)

    lines = [
        "# Routine index",
        "",
        "This file is generated from the Mesen CDL trace and the routine names in",
        "`tools/symbols.py`.  Names are working names: they describe the observed",
        "behavior and call graph, not original source symbols.  Addresses are CPU",
        "addresses inside each PRG bank.",
        "",
        "`loc_XXXX` labels are intra-routine branch targets and are intentionally",
        "not listed as separate routines.",
        "",
        "Sizes are approximate: routines that use inline data after a JSR (text or",
        "pointer tables) can appear shorter in this table than the bytes they occupy.",
        "",
    ]
    for bank in range(16):
        base = BASES[bank]
        labels = all_labels[bank]
        insn = traces[bank][0]
        starts = set()
        for a, name in labels.items():
            if a not in insn:
                continue
            if (bank, a) in NAMES or a in jsr_targets[bank] or (bank, a) in inline[bank]:
                starts.add(a)
        if not starts:
            continue
        ordered = sorted(starts)
        lines.append(f"## Bank {bank:02d}  (${base:04X}-${base + 0x3FFF:04X})")
        lines.append("")
        lines.append("| Address | Name | Approx. bytes | Callers | Summary |")
        lines.append("|---:|---|---:|---:|---|")
        for idx, a in enumerate(ordered):
            name = labels.get(a, f"sub_{a:04X}")
            body = collect_func(insn, a, starts, base, base + 0x4000)
            size = sum(i.size for i in body.values())
            doc = DOCS.get((bank, a), {})
            summary = " ".join(doc.get("summary", []))
            cs = callers.get(a, [])
            caller_text = f"{len(cs)}" if cs else "0"
            lines.append(f"| `${a:04X}` | `{name}` | {size} | {caller_text} | {summary} |")
        lines.append("")
        if inline[bank]:
            lines.append("### Inline RAM routines")
            lines.append("")
            lines.append("| Source address | Name | Bytes |")
            lines.append("|---:|---|---:|")
            for start, block in sorted(inline[bank].items()):
                name = labels.get(start, f"inline_{start:04X}")
                size = sum(i.size for _, i in block)
                lines.append(f"| `${start:04X}` | `{name}` | {size} |")
            lines.append("")

    (OUT / "FUNCTIONS.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    bank_lines = [
        "# Bank / resource map",
        "",
        "| Bank | CPU window | Role | Code bytes | Data resource |",
        "|---:|---|---|---:|---|",
    ]
    roles = {
        0: "Character/sprite/background tiles",
        1: "16x16 kanji + character graphics",
        2: "16x16 kanji + portrait/title graphics",
        3: "Title/portrait graphics",
        4: "Portrait graphics",
        5: "Map chip graphics",
        6: "Map layout/event data",
        7: "Party/list screen and event code",
        8: "Sound driver + music data",
        9: "UI graphics + 1bpp kana font",
        10: "Split message pointer table + editable .dtx text",
        11: "Split message pointer table + editable .dtx text",
        12: "Enemy/town/item/weapon tables",
        13: "Officer status/name-entry code + dictionary",
        14: "Gameplay/menu code + embedded tables",
        15: "Fixed bank: main loop, text engine, NMI, bank switching",
    }
    from decompile import BANK_RESOURCE
    for b in range(16):
        code = sum(i.size for i in traces[b][0].values())
        rid = BANK_RESOURCE.get(b) or "split PNG resources"
        bank_lines.append(f"| {b:02d} | `${BASES[b]:04X}` | {roles[b]} | {code} | `{rid}` |")
    (OUT / "BANKS.md").write_text("\n".join(bank_lines) + "\n", encoding="utf-8")
    print(f"wrote {OUT / 'FUNCTIONS.md'}")
    print(f"wrote {OUT / 'BANKS.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
