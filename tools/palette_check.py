#!/usr/bin/env python3
"""Palette gate: every palette the kanji ROM loads through load_text_graphics
must equal what the ORIGINAL routine would produce from the ORIGINAL tables
(bank 15 data_C5EF / data_C6B2 / data_C6C2), given the same index, $A5 and
buffer.  Timing-independent: it checks each load, not a frame sequence.

Usage: python tools/palette_check.py [kanji.nes]
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from mesen_run import MESEN, RUN_DIR, fresh_battery  # noqa: E402

OUT = ROOT / "out" / "test" / "r12"


def expected(fixed: bytes, idx: int, a5: int, before: bytes) -> bytes:
    rb = lambda a: fixed[a - 0xC000]
    p = rb(0xC6B2 + idx) | (rb(0xC6C2 + idx) << 8)
    buf = bytearray(before)
    x = rb(p)
    y = 0
    while True:
        y += 1
        v = rb(p + y)
        if v & 0x80:
            break
        buf[x & 0x1F] = v
        x = (x + 1) & 0xFF
        if x == 0:
            break
    if a5:
        a, yy = a5, 0
        while yy < 0x20:
            if a & 1:
                for k in range(4):
                    buf[yy + k] = 0x0F
            a >>= 1
            yy += 4
    return bytes(buf)


def main() -> int:
    kanji = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "decomp" / "build" / "rom_kanji.nes"
    lst = (ROOT / "decomp" / "build" / "kanji" / "mmc3_b15.lst").read_text(encoding="utf-8", errors="ignore")
    m = re.search(r"^0(C[0-9A-F]{3}) 60\s+rts", lst[lst.index("load_text_graphics:"):], re.M)
    lua_src = (ROOT / "tools" / "lua" / "palette_loads.lua").read_text(encoding="utf-8")
    lua_src = re.sub(r"local A_EXIT  = 0x[0-9A-F]{4}", f"local A_EXIT  = 0x{m.group(1)}", lua_src)
    lua = OUT / "palette_loads_run.lua"
    lua.write_text(lua_src, encoding="utf-8")
    name = "palloads"
    fresh_battery(name)
    copy = RUN_DIR / f"{name}.nes"
    copy.write_bytes(kanji.read_bytes())
    subprocess.run([str(MESEN), "--testRunner", str(copy), str(lua)], timeout=900)
    fixed = (ROOT / "decomp" / "build" / "rom.nes").read_bytes()[16 + 15 * 0x4000:16 + 16 * 0x4000]
    rows = (OUT / "palette_loads.txt").read_text(encoding="utf-8").split()
    bad = 0
    n = 0
    idxs = set()
    for i in range(0, len(rows), 5):
        frame, idx, a5, before, after = rows[i:i + 5]
        n += 1
        idxs.add(int(idx, 16))
        want = expected(fixed, int(idx, 16), int(a5, 16), bytes.fromhex(before))
        if want != bytes.fromhex(after):
            bad += 1
            print(f"frame {frame} index {idx}: got {after} want {want.hex().upper()}")
    print(f"palette gate: {n} loads (indexes {sorted(idxs)}), {bad} wrong")
    return 1 if bad or n == 0 else 0


if __name__ == "__main__":
    raise SystemExit(main())
