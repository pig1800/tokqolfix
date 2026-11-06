#!/usr/bin/env python3
"""Render raw PRG as 16x16 glyphs assuming 4 consecutive 8x8 tiles."""
import argparse
from PIL import Image
from rom import Rom

def tile_pixels(data, o):
    rows = []
    for y in range(8):
        p0 = data[o+y]; p1 = data[o+8+y]
        row = [((p0>>(7-x))&1) | (((p1>>(7-x))&1)<<1) for x in range(8)]
        rows.append(row)
    return rows

def render16(data, order='col', per_row=32, max_glyphs=None, scale=2, start=0, bg=255):
    n = (len(data)-start)//64
    if max_glyphs: n = min(n, max_glyphs)
    rows = (n+per_row-1)//per_row
    img = Image.new('L', (per_row*16*scale, rows*16*scale), bg)
    px = img.load()
    for g in range(n):
        o = start + g*64
        px4 = [tile_pixels(data, o+i*16) for i in range(4)]
        if order == 'col':   # TL, BL, TR, BR
            placement = [px4[0], px4[2], px4[1], px4[3]]
        else:                # TL, TR, BL, BR
            placement = [px4[0], px4[1], px4[2], px4[3]]
        for qi, tile in enumerate(placement):
            qx = (qi % 2)*8; qy = (qi//2)*8
            for y in range(8):
                for x in range(8):
                    v = tile[y][x]
                    col = [bg,170,85,0][v]
                    for sy in range(scale):
                        for sx in range(scale):
                            gx = (g%per_row)*16*scale + (qx+x)*scale+sx
                            gy = (g//per_row)*16*scale + (qy+y)*scale+sy
                            px[gx,gy] = col
    return img

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out')
    ap.add_argument('--offset', type=lambda s:int(s,0), default=0)
    ap.add_argument('--length', type=lambda s:int(s,0), default=None)
    ap.add_argument('--order', choices=['col','row'], default='col')
    ap.add_argument('--per-row', type=int, default=32)
    ap.add_argument('--max-glyphs', type=int, default=None)
    ap.add_argument('--scale', type=int, default=2)
    a = ap.parse_args()
    r = Rom()
    data = r.prg[a.offset:a.offset+a.length] if a.length else r.prg[a.offset:]
    img = render16(data, a.order, a.per_row, a.max_glyphs, a.scale)
    img.save(a.out)
    print(f"saved {a.out} {img.size}")

if __name__ == '__main__':
    main()
