#!/usr/bin/env python3
"""Prepare a four-screen Mesen 2 save state (tools/mss_4screen.py) for the
dialogue-canvas build (map-canvas step 3).

Usage:
    python -I tools/mss_canvas.py <in.mss> <out.mss> [--keep]

The canvas build runs code from battery RAM at $7900 (canvas_ram.asm,
installed at reset) and keeps its state in internal RAM $0780-$07FF.  A
state saved by an earlier build has neither: this copies the current
build's image (decomp/build/kanji/canvas_ram.bin) into the state's
battery RAM and clears $0780-$07FF (no canvas shown).  A state with an
open window keeps the window in the visible nametable, as the earlier
build drew it; the canvas starts with the next window.

--keep: a state saved by a canvas build (same canvas state layout, older
RAM code): install the image and keep $0780-$07FF, so an open canvas
stays up.
"""
from __future__ import annotations

import importlib.util
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
IMAGE = ROOT / "decomp" / "build" / "kanji" / "canvas_ram.bin"
CV_RAM = 0x7900
_spec = importlib.util.spec_from_file_location("mss_to_mmc3", HERE / "mss_to_mmc3.py")
_m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_m)
FOUR_SCREENS = 4


def convert(src: str, dst: str, keep: bool = False) -> None:
    head, recs = _m.read(src)
    d = {k: v for k, v in recs}
    mirror, = struct.unpack("<i", d["mapper.mirroringType"])
    if mirror != FOUR_SCREENS:
        raise SystemExit(f"{src}: not a four-screen state (tools/mss_4screen.py first)")
    image = IMAGE.read_bytes()
    sram = bytearray(d["mapper.saveRam"])
    base = CV_RAM - 0x6000
    sram[base:base + len(image)] = image
    ram = bytearray(d["memoryManager.internalRam"])
    if not keep:
        ram[0x780:0x800] = bytes(0x80)
    out = []
    for k, v in recs:
        if k == "mapper.saveRam":
            v = bytes(sram)
        elif k == "memoryManager.internalRam":
            v = bytes(ram)
        out.append([k, v])
    _m.write(dst, head, out)
    print(f"{dst}: canvas RAM code ({len(image)} bytes) installed, canvas state "
          + ("kept" if keep else "cleared"))


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--keep"]
    if len(args) != 2:
        raise SystemExit(__doc__)
    convert(args[0], args[1], keep="--keep" in sys.argv[1:])
