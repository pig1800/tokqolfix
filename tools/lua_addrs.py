#!/usr/bin/env python3
"""Rewrite hack-bank addresses in Lua test scripts from the build listing.

A Lua line of the form   local NAME = 0x1234  -- @label@
gets 0x1234 replaced by the address of `label:` in
decomp/build/kanji/hack.lst, kanji_overlay.lst or mmc3_b15.lst (first
listing that defines it).  Usage: python tools/lua_addrs.py <lua>...
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LSTS = [ROOT / "decomp" / "build" / "kanji" / n
        for n in ("hack.lst", "kanji_overlay.lst", "mmc3_b15.lst")]


def labels() -> dict[str, int]:
    out: dict[str, int] = {}
    for lst in LSTS:
        for line in lst.read_text(encoding="utf-8", errors="ignore").splitlines():
            m = re.match(r"^0([0-9A-F]{4})\s+([A-Za-z_][A-Za-z0-9_]*):", line)
            if m and m.group(2) not in out:
                out[m.group(2)] = int(m.group(1), 16)
    return out


def main() -> int:
    lab = labels()
    rc = 0
    for name in sys.argv[1:]:
        p = Path(name)
        src = p.read_text(encoding="utf-8")

        def fix(m: re.Match) -> str:
            nonlocal rc
            label = m.group(3)
            if label not in lab:
                print(f"{p}: unknown label {label}", file=sys.stderr)
                rc = 1
                return m.group(0)
            return f"{m.group(1)}0x{lab[label]:04X}{m.group(2)}@{label}@"

        new = re.sub(r"(=\s*)0x[0-9A-Fa-f]{4}(\s*--\s*)@([A-Za-z_0-9]+)@", fix, src)
        if new != src:
            p.write_text(new, encoding="utf-8")
            print(f"updated {p}")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
