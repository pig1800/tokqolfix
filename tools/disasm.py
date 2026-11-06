#!/usr/bin/env python3
"""Linear 6502 disassembler for a PRG bank/range using py65."""
import sys, argparse
from py65.disassembler import Disassembler
from py65.devices.mpu6502 import MPU
from rom import Rom

def make_mpu(data, base):
    mpu = MPU()
    mem = [0]*0x10000
    mem[base:base+len(data)] = data
    mpu.memory = mem
    return mpu

def disasm(r, bank, start, length, base=None):
    if base is None:
        base = 0x8000 if bank < r.prg_banks-1 else 0xC000
    data = r.bank(bank)
    end = min(len(data), start+length)
    mpu = make_mpu(data, base)
    d = Disassembler(mpu)
    pc = start
    out = []
    while pc < end:
        try:
            n, text = d.instruction_at(base + pc)
        except Exception as e:
            n, text = 1, f".byte ${data[pc]:02X}"
        if n == 0: n = 1
        out.append((base+pc, data[pc:pc+n].hex(' '), text))
        pc += n
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('bank', type=lambda s: int(s,0))
    ap.add_argument('start', type=lambda s: int(s,0))
    ap.add_argument('length', type=lambda s: int(s,0), nargs='?', default=0x100)
    ap.add_argument('--base', type=lambda s: int(s,0), default=None)
    a = ap.parse_args()
    r = Rom()
    for addr, raw, text in disasm(r, a.bank, a.start, a.length, a.base):
        print(f"{addr:04X}: {raw:<9} {text}")

if __name__ == '__main__':
    main()
