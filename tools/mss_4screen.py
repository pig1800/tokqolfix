#!/usr/bin/env python3
"""Convert a Mesen 2 save state of the two-screen MMC3 kanji build into one
for the four-screen build (map-canvas step 2).

Usage:
    python -I tools/mss_4screen.py <in.mss> <out.mss>

The two-screen build mirrors $2800/$2C00 onto $2000/$2400 (vertical
mirroring).  The four-screen build has 4 KiB of nametable RAM and keeps
the map in a 60-row ring: world metarow 15 * s + r in the vertical half
s & 1, PPUCTRL bit 1 = the camera's top screen & 1.  The state's 2 KiB of
nametables are copied into both vertical halves (what the two-screen
build showed, wherever the camera's rows fall), the PPU's nametable pages
are remapped, and in map mode PPUCTRL's shadow ($FF) gets bit 1 from the
camera position (text_y:text_x - 7 rows), and an open window's row
($0177) gets bit 6 when its corner shows from the lower half.  A state in the middle of a
vertical step (scroll_y not on the camera's row) is refused.
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
    if "mapper.registers" not in d:
        raise SystemExit(f"{src}: not an MMC3 state")
    mirror, = struct.unpack("<i", d["mapper.mirroringType"])
    if mirror == FOUR_SCREENS:
        raise SystemExit(f"{src}: already four-screen")
    nt = d["mapper.nametableRam"]
    if len(nt) != 0x800:
        raise SystemExit(f"{src}: nametable RAM is {len(nt)} bytes")
    off = list(struct.unpack("<64i", d["mapper.chrMemoryOffset"]))
    for p in range(0x20, 0x40):
        off[p] = ((p - 0x20) & 0x0F) * 0x100
    ram = bytearray(d["memoryManager.internalRam"])
    ty, tx, sy, ctrl = ram[0x61], ram[0x60], ram[0xFC], ram[0xFF]
    ty2, tx2, sx = ram[0x63], ram[0x62], ram[0xFD]
    top = ty * 15 + tx - 7
    left = ty2 * 16 + tx2 - 8
    note = "not map mode, PPUCTRL shadow kept"
    camera = (tx < 15 and tx2 < 16 and sy == (top % 15) * 16
              and sx == (left % 16) * 16 and (ctrl & 1) == (left // 16) & 1)
    if camera:
        ram[0xFF] = (ctrl & 0xFD) | (((top // 15) & 1) << 1)
        note = f"map camera top screen {top // 15}: $FF {ctrl:02X} -> {ram[0xFF]:02X}"
        # An open window (kanji band): its corner row as the four-screen
        # build sees it, in the camera's ring (KANJI_WIN_ROW bit 6).
        if ram[0x176]:
            wr = ram[0x177] & 0x1F
            top_ring = ((ram[0xFF] >> 1) & 1) * 30 + (sy >> 3)
            ring = top_ring + (wr - (sy >> 3)) % 30
            ram[0x177] = wr | (0x40 if ring % 60 >= 30 else 0)
            note += f"; window row {wr} -> ${ram[0x177]:02X}"
    elif tx < 15 and tx2 < 16 and sx == (left % 16) * 16 and (sy & 0x0F) and sy < 0xF0:
        raise SystemExit(f"{src}: mid-step state (scroll_y {sy:02X}); save at rest")
    out = []
    for k, v in recs:
        if k == "mapper.nametableRam":
            v = nt + nt
        elif k == "mapper.chrMemoryOffset":
            v = struct.pack("<64i", *off)
        elif k == "mapper.mirroringType":
            v = struct.pack("<i", FOUR_SCREENS)
        elif k == "memoryManager.internalRam":
            v = bytes(ram)
        out.append([k, v])
    _m.write(dst, head, out)
    print(f"{dst}: four-screen; {note}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    convert(sys.argv[1], sys.argv[2])
