#!/usr/bin/env python3
"""Basic iNES/ROM helpers for Tenchi o Kurau analysis."""
import os, sys, struct

ROM_PATH = os.path.join(os.path.dirname(__file__), '..', 'Tenchi o Kurau (Japan) (Rev 1).nes')

class Rom:
    def __init__(self, path=ROM_PATH):
        self.path = os.path.abspath(path)
        data = open(self.path, 'rb').read()
        self.header = data[:16]
        assert self.header[:4] == b'NES\x1a'
        self.prg_banks = self.header[4]
        self.chr_banks = self.header[5]
        self.flags6 = self.header[6]
        self.flags7 = self.header[7]
        self.prg = data[16:16 + self.prg_banks * 0x4000]
        self.chr = data[16 + self.prg_banks * 0x4000:]
        self.mapper = (self.flags6 >> 4) | (self.flags7 & 0xF0)
        self.nes2 = (self.flags7 & 0x0C) == 0x08
    def bank(self, n):
        return self.prg[n*0x4000:(n+1)*0x4000]
    def byte(self, bank, addr):
        """addr is CPU $8000-$FFFF; bank selects 16K PRG bank."""
        return self.prg[bank*0x4000 + (addr & 0x3FFF)]
    def cpu_to_file(self, bank, addr):
        return 16 + bank*0x4000 + (addr & 0x3FFF)
    def word(self, bank, addr):
        o = bank*0x4000 + (addr & 0x3FFF)
        return self.prg[o] | (self.prg[o+1] << 8)

def main():
    r = Rom()
    print(f"path={r.path}")
    print(f"PRG banks={r.prg_banks} ({len(r.prg)} bytes), CHR banks={r.chr_banks} ({len(r.chr)} bytes)")
    print(f"flags6={r.flags6:02X} flags7={r.flags7:02X} mapper={r.mapper} NES2.0={r.nes2}")
    print("header:", r.header.hex(' '))
    # vectors in last bank
    for b in [0, r.prg_banks-1]:
        base = b*0x4000
        nmi = r.prg[base+0x3FFA] | (r.prg[base+0x3FFB]<<8)
        rst = r.prg[base+0x3FFC] | (r.prg[base+0x3FFD]<<8)
        irq = r.prg[base+0x3FFE] | (r.prg[base+0x3FFF]<<8)
        print(f"bank {b:2d}: NMI=${nmi:04X} RESET=${rst:04X} IRQ=${irq:04X}")

if __name__ == '__main__':
    main()
