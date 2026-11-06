#!/usr/bin/env python3
"""Export and rebuild editable NES graphics resources.

The original ROM stores CHR RAM tiles as raw 2bpp (or sometimes 1bpp) byte
blocks in PRG.  This tool turns those blocks into ordinary PNG images while
keeping a manifest that records the exact PRG bank/offset/length.  The build
step converts the PNG back to bytes and verifies the round trip against the
original ROM.

Usage:
    python tools/assets.py export          # ROM -> assets/*.png + manifest
    python tools/assets.py build           # PNG -> decomp/build/assets/*.chr
    python tools/assets.py verify          # verify PNG round trip only
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ROM_PATH = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
ASSETS = ROOT / "assets"
BUILD_ASSETS = ROOT / "decomp" / "build" / "assets"
MANIFEST = ASSETS / "manifest.json"

PALETTE2 = [(0, 0, 0), (85, 85, 85), (170, 170, 170), (255, 255, 255)]
PALETTE1 = [(0, 0, 0), (255, 255, 255)]
COLOR2 = {c: i for i, c in enumerate(PALETTE2)}
COLOR1 = {c: i for i, c in enumerate(PALETTE1)}


@dataclass(frozen=True)
class Resource:
    id: str
    bank: int
    offset: int
    length: int
    kind: str  # chr2, glyph16, font1, bin
    path: str  # relative to assets/


RESOURCES = [
    # Raw 2bpp tile banks.  These are the character/sprite/background sets the
    # game copies into CHR RAM.
    Resource("bank00_chr", 0, 0x0000, 0x4000, "chr2", "graphics/bank00_chr.png"),
    Resource("bank01_header", 1, 0x0000, 0x0010, "bin", "data/bank01_header.bin"),
    Resource("bank01_kanji", 1, 0x0010, 0x1A00, "glyph16", "fonts/kanji_16x16_bank01.png"),
    Resource("bank01_gfx", 1, 0x1A10, 0x25F0, "chr2", "graphics/bank01_chr.png"),
    Resource("bank02_header", 2, 0x0000, 0x0010, "bin", "data/bank02_header.bin"),
    Resource("bank02_kanji", 2, 0x0010, 0x0800, "glyph16", "fonts/kanji_16x16_bank02.png"),
    Resource("bank02_gfx", 2, 0x0810, 0x37F0, "chr2", "graphics/bank02_chr.png"),
    Resource("bank03_chr", 3, 0x0000, 0x4000, "chr2", "graphics/bank03_chr.png"),
    Resource("bank04_chr", 4, 0x0000, 0x4000, "chr2", "graphics/bank04_chr.png"),
    Resource("bank05_chr", 5, 0x0000, 0x4000, "chr2", "graphics/bank05_chr.png"),
    # Bank 9 is mixed: 2bpp UI graphics, the 1bpp kana font, then 2bpp UI.
    Resource("bank09_ui_a", 9, 0x0000, 0x3A00, "chr2", "graphics/bank09_ui_a.png"),
    Resource("bank09_kana", 9, 0x3A00, 0x0400, "font1", "fonts/kana_8x8.png"),
    Resource("bank09_ui_b", 9, 0x3E00, 0x0200, "chr2", "graphics/bank09_ui_b.png"),
    # Binary data/text resources (exact bytes, not images).
    Resource("bank06_map", 6, 0x0000, 0x4000, "bin", "data/bank06_map.bin"),
    Resource("bank10_messages", 10, 0x0000, 0x4000, "bin", "text/bank10_messages.bin"),
    Resource("bank11_messages", 11, 0x0000, 0x4000, "bin", "text/bank11_messages.bin"),
    Resource("bank12_tables", 12, 0x0000, 0x4000, "bin", "data/bank12_tables.bin"),
    # Whole-bank fallbacks for data embedded in code banks.  Only the data
    # ranges are included by the assembly, never the code ranges.
    Resource("bank07_data", 7, 0x0000, 0x4000, "bin", "data/bank07.bin"),
    Resource("bank08_data", 8, 0x0000, 0x4000, "bin", "data/bank08.bin"),
    Resource("bank13_data", 13, 0x0000, 0x4000, "bin", "data/bank13.bin"),
    Resource("bank14_data", 14, 0x0000, 0x4000, "bin", "data/bank14.bin"),
    Resource("bank15_data", 15, 0x0000, 0x4000, "bin", "data/bank15.bin"),
]


def prg() -> bytes:
    return ROM_PATH.read_bytes()[16:]


def bank_bytes(bank: int) -> bytes:
    return prg()[bank * 0x4000:(bank + 1) * 0x4000]


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def tile_pixels2(tile: bytes):
    """Yield (x, y, color-index) for one 16-byte NES 2bpp tile."""
    p0, p1 = tile[:8], tile[8:]
    for y in range(8):
        a, b = p0[y], p1[y]
        for x in range(8):
            bit = 7 - x
            yield x, y, ((a >> bit) & 1) | (((b >> bit) & 1) << 1)


def tile_pixels1(tile: bytes):
    for y in range(8):
        a = tile[y]
        for x in range(8):
            yield x, y, (a >> (7 - x)) & 1


def decode_chr2(data: bytes) -> Image.Image:
    n = len(data) // 16
    cols = 16
    rows = (n + cols - 1) // cols
    img = Image.new("RGB", (cols * 8, rows * 8), PALETTE2[0])
    px = img.load()
    for t in range(n):
        tile = data[t * 16:(t + 1) * 16]
        ox, oy = (t % cols) * 8, (t // cols) * 8
        for x, y, c in tile_pixels2(tile):
            px[ox + x, oy + y] = PALETTE2[c]
    return img


def encode_chr2(img: Image.Image, length: int) -> bytes:
    if img.width % 8 or img.height % 8:
        raise ValueError(f"tile sheet dimensions must be multiples of 8, got {img.size}")
    if img.width != 128:
        raise ValueError(f"2bpp tile sheet must be 128 px wide (16 tiles), got {img.width}")
    px = img.convert("RGB").load()
    out = bytearray()
    n = length // 16
    for t in range(n):
        tx, ty = t % 16, t // 16
        p0 = bytearray(8)
        p1 = bytearray(8)
        for y in range(8):
            for x in range(8):
                rgb = px[tx * 8 + x, ty * 8 + y]
                try:
                    c = COLOR2[rgb]
                except KeyError:
                    raise ValueError(f"color {rgb} at tile ({tx},{ty}) pixel ({x},{y}) is not a NES 2bpp color")
                p0[y] |= (c & 1) << (7 - x)
                p1[y] |= ((c >> 1) & 1) << (7 - x)
        out += p0 + p1
    if len(out) != length:
        raise ValueError(f"2bpp resource length mismatch: image gives {len(out)}, expected {length}")
    return bytes(out)


def decode_glyph16(data: bytes) -> Image.Image:
    n = len(data) // 64
    cols = 16
    rows = (n + cols - 1) // cols
    img = Image.new("RGB", (cols * 16, rows * 16), PALETTE2[0])
    px = img.load()
    for g in range(n):
        glyph = data[g * 64:(g + 1) * 64]
        # Four tiles in column-major order: TL, BL, TR, BR.
        for ti, (ox, oy) in enumerate(((0, 0), (0, 8), (8, 0), (8, 8))):
            tile = glyph[ti * 16:(ti + 1) * 16]
            bx, by = (g % cols) * 16 + ox, (g // cols) * 16 + oy
            for x, y, c in tile_pixels2(tile):
                px[bx + x, by + y] = PALETTE2[c]
    return img


def encode_glyph16(img: Image.Image, length: int) -> bytes:
    if img.width != 256 or img.height % 16:
        raise ValueError(f"glyph sheet must be 256 px wide and a multiple of 16 px high, got {img.size}")
    px = img.convert("RGB").load()
    out = bytearray()
    n = length // 64
    for g in range(n):
        gx, gy = g % 16, g // 16
        for ox, oy in ((0, 0), (0, 8), (8, 0), (8, 8)):
            p0 = bytearray(8)
            p1 = bytearray(8)
            for y in range(8):
                for x in range(8):
                    rgb = px[gx * 16 + ox + x, gy * 16 + oy + y]
                    try:
                        c = COLOR2[rgb]
                    except KeyError:
                        raise ValueError(f"color {rgb} at glyph ({gx},{gy}) is not a NES 2bpp color")
                    p0[y] |= (c & 1) << (7 - x)
                    p1[y] |= ((c >> 1) & 1) << (7 - x)
            out += p0 + p1
    if len(out) != length:
        raise ValueError(f"glyph resource length mismatch: image gives {len(out)}, expected {length}")
    return bytes(out)


def decode_font1(data: bytes) -> Image.Image:
    n = len(data) // 8
    cols = 16
    rows = (n + cols - 1) // cols
    img = Image.new("RGB", (cols * 8, rows * 8), PALETTE1[0])
    px = img.load()
    for t in range(n):
        tile = data[t * 8:(t + 1) * 8]
        ox, oy = (t % cols) * 8, (t // cols) * 8
        for x, y, c in tile_pixels1(tile):
            px[ox + x, oy + y] = PALETTE1[c]
    return img


def encode_font1(img: Image.Image, length: int) -> bytes:
    if img.width != 128 or img.height % 8:
        raise ValueError(f"1bpp font sheet must be 128 px wide and a multiple of 8 px high, got {img.size}")
    px = img.convert("RGB").load()
    out = bytearray()
    n = length // 8
    for t in range(n):
        tx, ty = t % 16, t // 16
        tile = bytearray(8)
        for y in range(8):
            for x in range(8):
                rgb = px[tx * 8 + x, ty * 8 + y]
                try:
                    c = COLOR1[rgb]
                except KeyError:
                    raise ValueError(f"color {rgb} at font tile ({tx},{ty}) is not black/white")
                tile[y] |= c << (7 - x)
        out += tile
    if len(out) != length:
        raise ValueError(f"1bpp resource length mismatch: image gives {len(out)}, expected {length}")
    return bytes(out)


def export() -> int:
    rom = prg()
    manifest = {"version": 1, "rom_sha256": sha256(ROM_PATH.read_bytes()), "resources": []}
    for r in RESOURCES:
        data = bank_bytes(r.bank)[r.offset:r.offset + r.length]
        if len(data) != r.length:
            raise ValueError(f"{r.id}: short read")
        path = ASSETS / r.path
        path.parent.mkdir(parents=True, exist_ok=True)
        if r.kind == "chr2":
            decode_chr2(data).save(path)
            back = encode_chr2(Image.open(path), r.length)
        elif r.kind == "glyph16":
            decode_glyph16(data).save(path)
            back = encode_glyph16(Image.open(path), r.length)
        elif r.kind == "font1":
            decode_font1(data).save(path)
            back = encode_font1(Image.open(path), r.length)
        elif r.kind == "bin":
            path.write_bytes(data)
            back = data
        else:
            raise ValueError(r.kind)
        if back != data:
            raise ValueError(f"{r.id}: generated resource does not round-trip")
        manifest["resources"].append({
            "id": r.id,
            "kind": r.kind,
            "bank": r.bank,
            "offset": r.offset,
            "length": r.length,
            "path": r.path,
            "sha256": sha256(data),
        })
        print(f"exported {r.id:18s} bank {r.bank:02d} ${r.offset:04X}..${r.offset + r.length - 1:04X}  {r.kind}")
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {MANIFEST}")
    return 0


def load_manifest():
    if not MANIFEST.exists():
        raise SystemExit(f"manifest not found: {MANIFEST}; run 'python tools/assets.py export' first")
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def build() -> int:
    manifest = load_manifest()
    BUILD_ASSETS.mkdir(parents=True, exist_ok=True)
    total = 0
    for r in manifest["resources"]:
        src = ASSETS / r["path"]
        dst = BUILD_ASSETS / (r["id"] + ".bin")
        if r["kind"] == "chr2":
            data = encode_chr2(Image.open(src), r["length"])
        elif r["kind"] == "glyph16":
            data = encode_glyph16(Image.open(src), r["length"])
        elif r["kind"] == "font1":
            data = encode_font1(Image.open(src), r["length"])
        else:
            data = src.read_bytes()
        if len(data) != r["length"]:
            raise ValueError(f"{r['id']}: built length {len(data)} != {r['length']}")
        dst.write_bytes(data)
        total += len(data)
        print(f"built {r['id']:18s} {len(data):5d} bytes")
    print(f"wrote {total} bytes to {BUILD_ASSETS}")
    return 0


def verify() -> int:
    manifest = load_manifest()
    rom = prg()
    ok = True
    for r in manifest["resources"]:
        src = ASSETS / r["path"]
        want = bank_bytes(r["bank"])[r["offset"]:r["offset"] + r["length"]]
        if r["kind"] == "chr2":
            got = encode_chr2(Image.open(src), r["length"])
        elif r["kind"] == "glyph16":
            got = encode_glyph16(Image.open(src), r["length"])
        elif r["kind"] == "font1":
            got = encode_font1(Image.open(src), r["length"])
        else:
            got = src.read_bytes()
        if got != want:
            first = next((i for i in range(min(len(got), len(want))) if got[i] != want[i]), min(len(got), len(want)))
            print(f"FAIL {r['id']}: first diff +0x{first:X}")
            ok = False
        else:
            print(f"ok   {r['id']}")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["export", "build", "verify"])
    args = ap.parse_args()
    if args.command == "export":
        return export()
    if args.command == "build":
        return build()
    return verify()


if __name__ == "__main__":
    raise SystemExit(main())
