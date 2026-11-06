#!/usr/bin/env python3
"""Merge Mesen/FCEUX CDL maps with bitwise OR.

Accepts raw 262144-byte maps or Mesen CDLv2 files (9-byte header).
"""
import argparse
import sys
from pathlib import Path

PRG_SIZE = 262144


def load(path: Path) -> bytes:
    data = path.read_bytes()
    if len(data) == PRG_SIZE + 9 and data[:5] == b"CDLv2":
        data = data[9:]
    if len(data) != PRG_SIZE:
        raise SystemExit(f"{path}: expected {PRG_SIZE} bytes, got {len(data)}")
    return data


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()
    out = bytearray(PRG_SIZE)
    for name in args.inputs:
        data = load(Path(name))
        for i, v in enumerate(data):
            out[i] |= v
    Path(args.output).write_bytes(out)
    print(f"wrote {args.output} ({sum(1 for v in out if v)} non-zero bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
