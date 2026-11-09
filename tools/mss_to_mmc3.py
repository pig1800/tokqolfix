#!/usr/bin/env python3
"""Convert a Mesen 2 save state of the SUROM (MMC1) kanji build into one
for the MMC3 build (revision 21).

Usage:
    python -I tools/mss_to_mmc3.py <in.mss> <out.mss>

A Mesen 2 state (format 4) is a header, a screenshot, the ROM name and a
zlib-compressed list of (key, uint32 size, bytes) records.  Mesen loads a
state into another mapper but keeps that mapper's power-on registers, so
the CHR/PRG mapping is wrong.  This replaces the MMC1 mapper records with
the MMC3 registers and mapping arrays the MMC3 build would have at the
same point:

  R0 = 4 * MMC1 CHR register 1 (scene 4 / band 8), R1 = 6 (scene, tiles
  $80-$FF), R2-R5 = 0-3 (sprites), R6/R7 = the 16 KiB bank's halves
  (MMC1 PRG register | CHR register 0 bit 4, the SUROM outer bit).
  $8000 = MMC3_SEL = $87 (the last select of the main thread's switch;
  the RAM byte $EB, the MMC1 lock, becomes that shadow).
  The CPU's interrupt-disable flag is cleared: the MMC1 build never ran
  cli, the MMC3 build does at reset (its scanline IRQ switches the band).
  OAM slot 0 (the MMC1 build's band sprite) is hidden: it is the game's
  again, and the game keeps it hidden.

Everything else (CPU, PPU, APU, RAM, CHR RAM, battery RAM, nametables)
is copied.  The state must not stop inside the rewritten bank-switch code
($C460-$C4CA), the reset or the NMI handler ($EE79-$EFC8, where the
main thread's flags sit on the stack); the tool refuses such a PC.
"""
from __future__ import annotations

import struct
import sys
import zlib

MMC1_KEYS = ("writeBuffer", "shiftCount", "wramDisable", "chrMode", "prgMode",
             "slotSelect", "chrReg0", "chrReg1", "prgReg", "lastWriteCycle",
             "lastChrReg")
SEL = 0x87


def read(path):
    d = open(path, "rb").read()
    if d[:3] != b"MSS":
        raise SystemExit(f"{path}: not a Mesen save state")
    fmt, = struct.unpack_from("<I", d, 7)
    if fmt != 4:
        raise SystemExit(f"{path}: state format {fmt}, this tool knows 4")
    o = 15
    _, _, _, _, csize = struct.unpack_from("<IIIII", d, o)
    o += 20 + csize
    n, = struct.unpack_from("<I", d, o)
    head, rest = d[:o + 4 + n], d[o + 4 + n:]
    if rest[0] != 1:
        raise SystemExit(f"{path}: uncompressed state body")
    usize, csz = struct.unpack_from("<II", rest, 1)
    data = zlib.decompress(rest[9:9 + csz])
    recs, i = [], 0
    while i < len(data):
        j = data.index(b"\x00", i)
        size, = struct.unpack_from("<I", data, j + 1)
        recs.append([data[i:j].decode("ascii"), data[j + 5:j + 5 + size]])
        i = j + 5 + size
    return head, recs


def write(path, head, recs):
    data = b"".join(k.encode("ascii") + b"\x00" + struct.pack("<I", len(v)) + v
                    for k, v in recs)
    comp = zlib.compress(data, 6)
    with open(path, "wb") as f:
        f.write(head + b"\x01" + struct.pack("<II", len(data), len(comp)) + comp)


def u32s(values):
    return struct.pack("<%di" % len(values), *values)


def convert(src, dst):
    head, recs = read(src)
    d = {k: v for k, v in recs}
    if "mapper.prgReg" not in d or "mapper.registers" in d:
        raise SystemExit(f"{src}: not an MMC1 state")
    pc, = struct.unpack("<H", d["cpu.pc"])
    if 0xC460 <= pc <= 0xC4CA or 0xF004 <= pc <= 0xF039:
        raise SystemExit(f"{src}: PC ${pc:04X} is inside rewritten mapper code")
    if 0xEE79 <= pc <= 0xEFC8:
        raise SystemExit(f"{src}: PC ${pc:04X} is inside the NMI handler")
    bank = (d["mapper.prgReg"][0] & 0x0F) | (d["mapper.chrReg0"][0] & 0x10)
    page = d["mapper.chrReg1"][0]
    if page not in (1, 2):
        raise SystemExit(f"{src}: CHR register 1 = {page}, expected page 1 or 2")
    regs = bytes((4 * page, 6, 0, 1, 2, 3, 2 * bank, 2 * bank + 1))

    # Mapping arrays (per 256-byte page): offsets, memory types, access.
    prg_off, prg_type, prg_acc = [-1] * 256, [0] * 256, [0] * 256
    for p in range(0x60, 0x80):                  # battery RAM
        prg_off[p], prg_type[p], prg_acc[p] = (p - 0x60) * 256, 1, 3
    for p in range(0x80, 0x100):                 # PRG ROM, 8 KiB slots
        slot = (p - 0x80) >> 5
        b8 = (regs[6], regs[7], 62, 63)[slot]
        prg_off[p], prg_type[p], prg_acc[p] = b8 * 8192 + (p & 0x1F) * 256, 0, 1
    chr_off, chr_type, chr_acc = [0] * 64, [2] * 64, [3] * 64
    k1 = (regs[2], regs[3], regs[4], regs[5], regs[0], regs[0] + 1, regs[1], regs[1] + 1)
    for p in range(32):                          # $0000-$1FFF, CHR mode 1
        chr_off[p] = k1[p >> 2] * 1024 + (p & 3) * 256
    for p in range(32, 64):                      # nametables, vertical mirroring
        q = (p - 32) & 0x0F
        chr_off[p], chr_type[p] = (q & 3) * 256 + (1024 if (q >> 2) & 1 else 0), 3

    mmc3 = [
        ["mapper.prgMemoryOffset", u32s(prg_off)],
        ["mapper.chrMemoryOffset", u32s(chr_off)],
        ["mapper.prgMemoryType", u32s(prg_type)],
        ["mapper.chrMemoryType", u32s(chr_type)],
        ["mapper.prgMemoryAccess", u32s(prg_acc)],
        ["mapper.chrMemoryAccess", u32s(chr_acc)],
    ]
    tail = [
        ["mapper.registers", regs],
        ["mapper.a12LowClock", bytes(8)],
        ["mapper.reg8000", bytes((SEL,))],
        ["mapper.regA000", bytes((0,))],
        ["mapper.regA001", bytes((0x80,))],
        ["mapper.currentRegister", bytes((SEL & 7,))],
        ["mapper.chrMode", bytes((1,))],
        ["mapper.prgMode", bytes((0,))],
        ["mapper.irqReloadValue", bytes((0,))],
        ["mapper.irqCounter", bytes((0,))],
        ["mapper.irqReload", bytes((0,))],
        ["mapper.irqEnabled", bytes((0,))],
        ["mapper.wramEnabled", bytes((1,))],
        ["mapper.wramWriteProtected", bytes((0,))],
    ]
    out = []
    for k, v in recs:
        if k.startswith("mapper.") and k[7:] in MMC1_KEYS:
            continue
        if k == "mapper.mirroringType":
            out.extend(mmc3)
            out.append([k, v])
            out.extend(tail)
            continue
        if k == "cpu.ps":
            v = bytes((v[0] & ~0x04 & 0xFF,))     # I clear (cli at reset)
        if k == "memoryManager.internalRam":
            ram = bytearray(v)
            ram[0xEB] = SEL                      # MMC3_SEL (was the MMC1 lock)
            ram[0x200] = 0xF8                    # OAM shadow slot 0 hidden
            v = bytes(ram)
        if k == "ppu.spriteRam":
            v = bytes((0xF8,)) + v[1:]           # OAM slot 0 hidden
        out.append([k, v])
    write(dst, head, out)
    return pc, bank, page


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    pc, bank, page = convert(sys.argv[1], sys.argv[2])
    print(f"{sys.argv[2]}: PC ${pc:04X}, bank {bank}, BG page {page}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
