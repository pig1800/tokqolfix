#!/usr/bin/env python3
"""Prepare a four-screen Mesen 2 save state (tools/mss_4screen.py) for the
renderer builds (map-canvas step 3 on).

Usage:
    python -I tools/mss_canvas.py <in.mss> <out.mss>

The renderer keeps its state in internal RAM $0780-$07FF.  A state saved
by an earlier build has none: this clears $0780-$07FF (no window drawn by
the renderer).  A state with an open window keeps the window in the
visible nametable, as the earlier build drew it; the renderer starts with
the next window.

(Until 2026-11-14 this also installed the RAM code at $7900 into the
state's battery RAM; that code is in bank 31 now, fixed_rt.asm, and the
new ROM never calls $7900.  A state saved by a build with RAM code keeps
its own copy, so a return into it from a state saved mid-call still works.)
"""
from __future__ import annotations

import importlib.util
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("mss_to_mmc3", HERE / "mss_to_mmc3.py")
_m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_m)
FOUR_SCREENS = 4


def convert(src: str, dst: str) -> None:
    head, recs = _m.read(src)
    d = {k: v for k, v in recs}
    mirror, = struct.unpack("<i", d["mapper.mirroringType"])
    if mirror != FOUR_SCREENS:
        raise SystemExit(f"{src}: not a four-screen state (tools/mss_4screen.py first)")
    ram = bytearray(d["memoryManager.internalRam"])
    ram[0x780:0x800] = bytes(0x80)
    out = []
    for k, v in recs:
        if k == "memoryManager.internalRam":
            v = bytes(ram)
        out.append([k, v])
    _m.write(dst, head, out)
    print(f"{dst}: renderer state cleared")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    convert(sys.argv[1], sys.argv[2])
