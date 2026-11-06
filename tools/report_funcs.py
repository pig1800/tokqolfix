#!/usr/bin/env python3
"""Print a compact human-readable routine report from functions.json."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", default="out/functions.json")
    ap.add_argument("bank", type=lambda s: int(s, 0))
    ap.add_argument("--start", type=lambda s: int(s, 0), default=0)
    ap.add_argument("--count", type=int, default=20)
    ap.add_argument("--insns", type=int, default=8)
    args = ap.parse_args()
    data = json.loads(Path(args.json).read_text())[str(args.bank)]
    funcs = [f for f in data["functions"] if f["start"] >= args.start]
    for f in funcs[:args.count]:
        print(f"\n=== ${f['start']:04X}-${f['end']-1:04X}  size={f['size']}  callers={len(f['callers'])}")
        if f["callers"]:
            print("  callers:", " ".join(f"${x:04X}" for x in f["callers"]))
        if f["calls"]:
            print("  calls:  ", " ".join(f"${x:04X}" for x in f["calls"]))
        if f["tail_calls"]:
            print("  tail:   ", " ".join(f"${x:04X}" for x in f["tail_calls"]))
        if f["writes"]:
            ws = ", ".join(f"${int(k):04X}x{v}" for k, v in f["writes"].items())
            print("  writes: ", ws)
        for ins in f["instructions"][:args.insns]:
            print(f"    ${ins['addr']:04X}: {ins['text']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
