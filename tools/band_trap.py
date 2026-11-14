#!/usr/bin/env python3
"""Name the message that stopped the CPU in the overlay's band_trap.

Since 2026-11-14 there is no band page.  A message that would have shown
its kanji there (outside map mode, the battle set's pool, the boot screens
and the opening oath) executes a JAM in the overlay with A = its text bank
and X/Y = its text address (low, high).  Read A, X and Y in Mesen's
debugger and run:

    python tools/band_trap.py 12 57 9C        (hex, as the debugger shows)
    python tools/band_trap.py A=12 X=57 Y=9C

It prints the message label (decomp/build/kanji/message_map.json, written
by the text compiler) and its text from the r14 dtx.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAP = ROOT / "decomp" / "build" / "kanji" / "message_map.json"


def main(argv: list[str]) -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    vals = [re.sub(r"^[AXYaxy]=", "", a) for a in argv]
    if len(vals) != 3:
        print(__doc__)
        return 2
    bank, lo, hi = (int(v.lstrip("$"), 16) for v in vals)
    addr = hi << 8 | lo
    table = json.loads(MAP.read_text(encoding="utf-8"))
    hits = [lab for lab, (b, a) in table.items() if b == bank and a == addr]
    if not hits:
        print(f"no message starts at bank {bank} ${addr:04X} (message_map.json is the last build's)")
        return 1
    sys.path.insert(0, str(ROOT / "tools"))
    import kanji_common
    import kanji_text
    texts = {}
    for path in kanji_common.DTX_FILES:
        for rec in kanji_text.parse_dtx(path):
            for lab in rec.labels:
                texts[lab] = rec.text
    for lab in hits:
        print(f"{lab}  (bank {bank} ${addr:04X})")
        print(f"  {texts.get(lab, '?')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
