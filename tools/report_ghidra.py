#!/usr/bin/env python3
"""Compact report from a SeedExport JSON file."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("json")
    ap.add_argument("--start", type=lambda s: int(s, 0), default=0)
    ap.add_argument("--count", type=int, default=40)
    ap.add_argument("--chars", type=int, default=420)
    args = ap.parse_args()
    d = json.loads(Path(args.json).read_text())
    funcs = [f for f in d["functions"] if int(f["entry"], 16) >= args.start]
    for f in funcs[:args.count]:
        c = re.sub(r"\s+", " ", f.get("c", "")).strip()
        print(f"\n=== {f['entry']}  size={f['size']}  callers={len(f['calling'])}  calls={len(f['called'])}")
        print(f"name={f['name']}")
        if f["calling"]:
            print("callers:", " ".join(f["calling"]))
        if f["called"]:
            print("called: ", " ".join(f["called"]))
        print("C:", c[:args.chars])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
