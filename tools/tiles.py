#!/usr/bin/env python3
"""Render raw PRG bytes as 2bpp 8x8 tiles to a contact sheet."""
import sys, os
from PIL import Image
from rom import Rom

def render_tiles(data, tile_offset=0, per_row=64, max_tiles=None, scale=2, bg=255, fg=0):
    n = len(data)//16
    if max_tiles: n = min(n, max_tiles)
    rows = (n + per_row - 1)//per_row
    img = Image.new('L', (per_row*8*scale, rows*8*scale), bg)
    px = img.load()
    for t in range(n):
        o = tile_offset + t*16
        if o+16 > len(data): break
        for y in range(8):
            p0 = data[o+y]
            p1 = data[o+8+y]
            for x in range(8):
                bit = 7-x
                v = ((p0>>bit)&1) | (((p1>>bit)&1)<<1)
                col = [bg, 170, 85, fg][v]
                for sy in range(scale):
                    for sx in range(scale):
                        px[(t%per_row)*8*scale + x*scale+sx, (t//per_row)*8*scale + y*scale+sy] = col
    return img

def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('out')
    ap.add_argument('--offset', type=lambda s:int(s,0), default=0)
    ap.add_argument('--length', type=lambda s:int(s,0), default=None)
    ap.add_argument('--per-row', type=int, default=64)
    ap.add_argument('--max-tiles', type=int, default=None)
    ap.add_argument('--scale', type=int, default=2)
    a = ap.parse_args()
    r = Rom()
    data = r.prg
    if a.length:
        data = data[a.offset:a.offset+a.length]
    else:
        data = data[a.offset:]
    img = render_tiles(data, 0, a.per_row, a.max_tiles, a.scale)
    img.save(a.out)
    print(f"saved {a.out} {img.size}, tiles={min(len(data)//16, a.max_tiles or 10**9)}")

if __name__ == '__main__':
    main()
