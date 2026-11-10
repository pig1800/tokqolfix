"""Map kanji-build CDLs (512 KiB PRG) onto the original PRG (256 KiB).

Only the code bits (0x0D) are kept: the kanji build reads ROM bytes the
original does not (block copies, hooks), so its data bit is not trusted.
Banks 0-14 sit at the same offsets; the fixed bank runs from bank 31
(0x7C000) in the kanji build.  A flag is kept only where the kanji byte
equals the original byte, and every flag within 2 bytes of a differing byte
is dropped (a hooked instruction must not leave a partial run behind).
usage: map_kanji_cdl.py <kanji.nes> <orig.nes> <out.bin> <cdl>...
Then OR the result into the original CDL (tools/merge_cdl.py).
"""
import sys
kr = open(sys.argv[1], "rb").read()[16:]
orr = open(sys.argv[2], "rb").read()[16:]
assert len(kr) == 0x80000 and len(orr) == 0x40000
k = bytearray(0x80000)
for p in sys.argv[4:]:
    d = open(p, "rb").read()
    assert len(d) == 0x80000, (p, len(d))
    for i, v in enumerate(d):
        k[i] |= v
out = bytearray(0x40000)
src = list(range(0x3C000)) + list(range(0x7C000, 0x80000))
bad = set()
for o, s in enumerate(src):
    if kr[s] != orr[o]:
        bad.add(o)
for o, s in enumerate(src):
    v = k[s]
    if o >= 0x3C000:
        s2 = o  # the kanji ROM's unpatched copy of bank 15
        if kr[s2] == orr[o]:
            v |= k[s2]
    out[o] = v & 0x0D        # code, jump target, sub entry: the data bit is dropped
for d in bad:
    for j in range(d - 2, d + 3):
        if 0 <= j < 0x40000:
            out[j] = 0
open(sys.argv[3], "wb").write(out)
per = [sum(1 for v in out[b*0x4000:(b+1)*0x4000] if v & 1) for b in range(16)]
print("differing bytes:", len(bad))
print("code bytes per bank:", per)
