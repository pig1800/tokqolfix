#!/usr/bin/env python3
"""Render CHR tiles with hex index labels."""
import sys, argparse
from PIL import Image, ImageDraw
sys.path.insert(0, '.')
from tools.rom import Rom

def tile_rows(data, o):
    rows=[]
    for y in range(8):
        p0=data[o+y]; p1=data[o+8+y]
        rows.append([((p0>>(7-x))&1)|(((p1>>(7-x))&1)<<1) for x in range(8)])
    return rows

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('binfile')
    ap.add_argument('out')
    ap.add_argument('--base', type=lambda s:int(s,0), default=0)
    ap.add_argument('--count', type=lambda s:int(s,0), default=256)
    ap.add_argument('--per-row', type=int, default=16)
    ap.add_argument('--scale', type=int, default=6)
    a=ap.parse_args()
    data=open(a.binfile,'rb').read()
    cw=8*a.scale+8; ch=8*a.scale+18
    rows=(a.count+a.per_row-1)//a.per_row
    img=Image.new('RGB',(a.per_row*cw, rows*ch),(255,255,255))
    d=ImageDraw.Draw(img)
    for i in range(a.count):
        o=a.base+i*16
        if o+16>len(data): break
        gx=(i%a.per_row)*cw+4; gy=(i//a.per_row)*ch+2
        rows_=tile_rows(data,o)
        for y in range(8):
            for x in range(8):
                c=[255,170,85,0][rows_[y][x]]
                d.rectangle([gx+x*a.scale,gy+y*a.scale,gx+(x+1)*a.scale-1,gy+(y+1)*a.scale-1],fill=(c,c,c))
        d.text((gx, gy+8*a.scale+2), f"{a.base//16+i:02X}", fill=(0,0,0))
    img.save(a.out)
    print('saved',a.out,img.size)

if __name__=='__main__':
    main()
