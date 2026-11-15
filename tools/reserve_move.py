#!/usr/bin/env python3
"""Move the reserve list of a battery save or a Mesen 2 state to the place
the kanji edition keeps it since 2026-11-15 (the list of 125, kanji.inc
LS_RESERVE): $6030-$606F (the original's 64) -> $6410-$644F, and the old
place cleared.  The game does not do this itself.

Usage:
    python -I tools/reserve_move.py [--check] <in> [<out>]

<in> is an 8 KiB battery save (.sav: $6000-$7FFF) or a Mesen 2 state
(.mss, format 4: its "mapper.saveRam" record).  Without <out> nothing is
written (a dry run that reports what would move).  <out> may be <in>.

In the battery RAM the list is moved in the live state ($6000-$67FF) and
in each save record ($6800-$6FFF, $7000-$77FF; a record is a copy of
$6000-$67FF, signature "5S" at bytes 8-9, at bytes 6-7 the 16-bit sum of
bytes 8-$7FF).  Moving bytes keeps that sum; the tool checks it before and
after.  A copy whose old place is empty is left alone; one whose new place
($6410-$648F) is not all 0 is refused (moved already, or something else
there).  $7800-$7FFF (the kanji edition's map engine RAM) is not touched.
"""
from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

OLD, NEW, N = 0x30, 0x410, 64          # offsets in a $6000-$67FF copy
NEW_SPAN = 0x80                        # $6410-$648F must be 0 before
COPIES = ((0x0000, "live state"), (0x0800, "record 1"), (0x1000, "record 2"))


def record_sum(c: bytes) -> int:
    return sum(c[8:0x800]) & 0xFFFF


def move(ram: bytearray, name: str) -> int:
    moved = 0
    for base, what in COPIES:
        c = ram[base:base + 0x800]
        old = bytes(c[OLD:OLD + N])
        is_rec = base != 0
        signed = c[8:10] == b"5S"
        if is_rec and not signed:
            print(f"{name}: {what}: no record")
            continue
        if not any(old):
            print(f"{name}: {what}: nothing at $6030")
            continue
        if any(c[NEW:NEW + NEW_SPAN]):
            raise SystemExit(f"{name}: {what}: $6410-$648F is not empty; refusing")
        if is_rec:
            stored = c[6] | c[7] << 8
            ok = record_sum(c) == stored
            print(f"{name}: {what}: checksum {'ok' if ok else 'BAD (left bad)'}")
        n = next((i for i, b in enumerate(old) if b == 0), N)
        c[NEW:NEW + N] = old
        c[OLD:OLD + N] = bytes(N)
        if is_rec:
            assert (record_sum(c) == stored) == ok
        ram[base:base + 0x800] = c
        moved += 1
        print(f"{name}: {what}: {n} officers moved to $6410")
    return moved


def read_mss(d: bytes):
    if d[:3] != b"MSS":
        raise SystemExit("not a Mesen save state")
    fmt, = struct.unpack_from("<I", d, 7)
    if fmt != 4:
        raise SystemExit(f"state format {fmt}, this tool knows 4")
    o = 15
    _, _, _, _, csize = struct.unpack_from("<IIIII", d, o)
    o += 20 + csize
    n, = struct.unpack_from("<I", d, o)
    head, rest = d[:o + 4 + n], d[o + 4 + n:]
    if rest[0] != 1:
        raise SystemExit("uncompressed state body")
    usize, csz = struct.unpack_from("<II", rest, 1)
    data = zlib.decompress(rest[9:9 + csz])
    recs, i = [], 0
    while i < len(data):
        j = data.index(b"\x00", i)
        size, = struct.unpack_from("<I", data, j + 1)
        recs.append([data[i:j].decode("ascii"), bytearray(data[j + 5:j + 5 + size])])
        i = j + 5 + size
    return head, recs


def write_mss(head: bytes, recs) -> bytes:
    data = b"".join(k.encode("ascii") + b"\x00" + struct.pack("<I", len(v)) + bytes(v)
                    for k, v in recs)
    comp = zlib.compress(data, 6)
    return head + b"\x01" + struct.pack("<II", len(data), len(comp)) + comp


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not 1 <= len(args) <= 2:
        print(__doc__)
        return 1
    src = Path(args[0])
    dst = Path(args[1]) if len(args) == 2 else None
    d = src.read_bytes()
    if d[:3] == b"MSS":
        head, recs = read_mss(d)
        ram = next((v for k, v in recs if k == "mapper.saveRam"), None)
        if ram is None or len(ram) != 0x2000:
            raise SystemExit(f"{src}: no 8 KiB battery RAM in the state")
        moved = move(ram, src.name)
        out = write_mss(head, recs)
    else:
        if len(d) != 0x2000:
            raise SystemExit(f"{src}: not an 8 KiB battery save")
        ram = bytearray(d)
        moved = move(ram, src.name)
        out = bytes(ram)
    if dst is None:
        print(f"{src.name}: dry run, {moved} copies would move")
    elif moved:
        dst.write_bytes(out)
        print(f"{src.name}: written to {dst}")
    elif dst != src:
        dst.write_bytes(d)
        print(f"{src.name}: unchanged, copied to {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
