#!/usr/bin/env python3
"""Make the release patch: a BPS patch from the original ROM to the kanji
edition, checked by applying it again.

Usage:
    python -I tools/make_bps.py [<source> <target> <patch>]

Defaults: `Tenchi o Kurau (Japan) (Rev 1).nes` at the repo root,
`decomp/build/rom_kanji.nes` (run the kanji build first) and
`out/release/tokqolfix.bps`.

The format is beat's BPS1.  The encoder looks for every run of at least
MIN_MATCH bytes that the source holds (at the same offset, SourceRead, or
anywhere, SourceCopy) or that the target has already produced
(TargetCopy), and stores only what matches nothing (TargetRead).  So the
original game's code and data that the kanji edition keeps, at the same
place or moved (bank 15 is bank 31 in the edition), come from the
player's ROM, not from the patch.  The 16-byte header is always stored,
so a copy whose header alone differs (an older iNES header) still gives
the right ROM if the patcher is told to ignore the source checksum.

After writing, the patch is applied by the decoder below (written from
the format, not shared with the encoder's bookkeeping) and the result
compared byte for byte with the target; the three CRC32s are checked too.
The patch goes under out/, which git ignores: it is a release asset, not
part of the repository.
"""
from __future__ import annotations

import hashlib
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEF_SRC = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
DEF_TGT = ROOT / "decomp" / "build" / "rom_kanji.nes"
DEF_OUT = ROOT / "out" / "release" / "tokqolfix.bps"

K = 6            # hash length for match candidates
CHAIN = 48       # most recent candidates tried per hash
MIN_MATCH = 4    # shortest copy worth a command
HEADER = 16      # the iNES header: always stored (TargetRead)

SOURCE_READ, TARGET_READ, SOURCE_COPY, TARGET_COPY = range(4)


def vlq(n: int) -> bytes:
    """beat's variable-length number: 7 bits a byte, low first, the last
    byte's bit 7 set, each continuation one less (no redundant forms)."""
    out = bytearray()
    while True:
        x = n & 0x7F
        n >>= 7
        if n == 0:
            out.append(0x80 | x)
            return bytes(out)
        out.append(x)
        n -= 1


def signed_vlq(d: int) -> bytes:
    return vlq((abs(d) << 1) | (1 if d < 0 else 0))


def match_len(a: bytes, ai: int, b: bytes, bi: int, limit: int) -> int:
    n = 0
    for step in (4096, 256, 16):
        while n + step <= limit and a[ai + n:ai + n + step] == b[bi + n:bi + n + step]:
            n += step
    while n < limit and a[ai + n] == b[bi + n]:
        n += 1
    return n


def encode(src: bytes, tgt: bytes, metadata: bytes = b"") -> bytes:
    out = bytearray(b"BPS1")
    out += vlq(len(src)) + vlq(len(tgt)) + vlq(len(metadata)) + metadata

    sidx: dict[bytes, list[int]] = {}
    for p in range(len(src) - K + 1):
        sidx.setdefault(src[p:p + K], []).append(p)
    tidx: dict[bytes, list[int]] = {}
    tins = 0                      # target positions indexed so far

    src_rel = tgt_rel = 0
    lit_start = -1
    i, T, S = 0, len(tgt), len(src)

    def flush_literal(end: int) -> None:
        nonlocal lit_start
        if lit_start >= 0:
            n = end - lit_start
            out.extend(vlq(((n - 1) << 2) | TARGET_READ))
            out.extend(tgt[lit_start:end])
            lit_start = -1

    while i < T:
        while tins < i and tins + K <= T:
            tidx.setdefault(tgt[tins:tins + K], []).append(tins)
            tins += 1
        best_gain, best = 0, None
        if i < HEADER:
            if lit_start < 0:
                lit_start = i
            i += 1
            continue
        if i < S:
            n = match_len(src, i, tgt, i, min(S, T) - i)
            if n >= MIN_MATCH:
                gain = n - len(vlq(((n - 1) << 2) | SOURCE_READ))
                if gain > best_gain:
                    best_gain, best = gain, (SOURCE_READ, n, 0)
        key = tgt[i:i + K]
        if len(key) == K:
            for p in reversed(sidx.get(key, ())[-CHAIN:]):
                n = match_len(src, p, tgt, i, min(S - p, T - i))
                gain = n - len(vlq(((n - 1) << 2) | SOURCE_COPY)) - len(signed_vlq(p - src_rel))
                if gain > best_gain:
                    best_gain, best = gain, (SOURCE_COPY, n, p)
            for p in reversed(tidx.get(key, ())[-CHAIN:]):
                n = match_len(tgt, p, tgt, i, T - i)
                gain = n - len(vlq(((n - 1) << 2) | TARGET_COPY)) - len(signed_vlq(p - tgt_rel))
                if gain > best_gain:
                    best_gain, best = gain, (TARGET_COPY, n, p)
        if best is None or best[1] < MIN_MATCH or best_gain <= 1:
            if lit_start < 0:
                lit_start = i
            i += 1
            continue
        flush_literal(i)
        cmd, n, p = best
        out += vlq(((n - 1) << 2) | cmd)
        if cmd == SOURCE_COPY:
            out += signed_vlq(p - src_rel)
            src_rel = p + n
        elif cmd == TARGET_COPY:
            out += signed_vlq(p - tgt_rel)
            tgt_rel = p + n
        i += n
    flush_literal(T)

    out += zlib.crc32(src).to_bytes(4, "little")
    out += zlib.crc32(tgt).to_bytes(4, "little")
    out += zlib.crc32(bytes(out)).to_bytes(4, "little")
    return bytes(out)


def apply(src: bytes, patch: bytes) -> bytes:
    """Apply a BPS1 patch, checking all three CRC32s."""
    if patch[:4] != b"BPS1":
        raise ValueError("not a BPS1 patch")
    if zlib.crc32(patch[:-4]) != int.from_bytes(patch[-4:], "little"):
        raise ValueError("patch CRC32 mismatch")
    pos = 4

    def num() -> int:
        nonlocal pos
        data, shift = 0, 1
        while True:
            x = patch[pos]
            pos += 1
            data += (x & 0x7F) * shift
            if x & 0x80:
                return data
            shift <<= 7
            data += shift

    ssize, tsize = num(), num()
    msize = num()                 # not pos += num(): pos is read first
    pos += msize
    if len(src) != ssize:
        raise ValueError(f"source is {len(src)} bytes, the patch wants {ssize}")
    if zlib.crc32(src) != int.from_bytes(patch[-12:-8], "little"):
        raise ValueError("source CRC32 mismatch")
    tgt = bytearray()
    sr = tr = 0
    end = len(patch) - 12
    while pos < end:
        data = num()
        cmd, n = data & 3, (data >> 2) + 1
        if cmd == SOURCE_READ:
            tgt += src[len(tgt):len(tgt) + n]
        elif cmd == TARGET_READ:
            tgt += patch[pos:pos + n]
            pos += n
        elif cmd == SOURCE_COPY:
            d = num()
            sr += -(d >> 1) if d & 1 else d >> 1
            tgt += src[sr:sr + n]
            sr += n
        else:
            d = num()
            tr += -(d >> 1) if d & 1 else d >> 1
            for _ in range(n):
                tgt.append(tgt[tr])
                tr += 1
    if len(tgt) != tsize:
        raise ValueError(f"made {len(tgt)} bytes, the patch says {tsize}")
    if zlib.crc32(tgt) != int.from_bytes(patch[-8:-4], "little"):
        raise ValueError("target CRC32 mismatch")
    return bytes(tgt)


def stats(patch: bytes) -> dict[int, list[int]]:
    """Count and total length of each command (for the report)."""
    pos = 4
    out = {c: [0, 0] for c in range(4)}

    def num() -> int:
        nonlocal pos
        data, shift = 0, 1
        while True:
            x = patch[pos]
            pos += 1
            data += (x & 0x7F) * shift
            if x & 0x80:
                return data
            shift <<= 7
            data += shift

    num(), num()
    msize = num()
    pos += msize
    while pos < len(patch) - 12:
        data = num()
        cmd, n = data & 3, (data >> 2) + 1
        out[cmd][0] += 1
        out[cmd][1] += n
        if cmd == TARGET_READ:
            pos += n
        elif cmd != SOURCE_READ:
            num()
    return out


def main(argv: list[str]) -> int:
    if len(argv) not in (1, 4):
        print(__doc__)
        return 2
    src_p, tgt_p, out_p = (DEF_SRC, DEF_TGT, DEF_OUT) if len(argv) == 1 else map(Path, argv[1:])
    src, tgt = src_p.read_bytes(), tgt_p.read_bytes()
    patch = encode(src, tgt)
    if apply(src, patch) != tgt:
        raise SystemExit("the patch does not reproduce the target")
    out_p.parent.mkdir(parents=True, exist_ok=True)
    out_p.write_bytes(patch)
    names = {SOURCE_READ: "SourceRead", TARGET_READ: "TargetRead",
             SOURCE_COPY: "SourceCopy", TARGET_COPY: "TargetCopy"}
    for c, (cnt, total) in stats(patch).items():
        print(f"  {names[c]:10s} {cnt:6d} commands, {total:7d} bytes")
    for what, data in (("source", src), ("target", tgt)):
        print(f"{what:6s} {len(data):7d} bytes  crc32 {zlib.crc32(data):08X}  "
              f"sha1 {hashlib.sha1(data).hexdigest()}")
    # (a BPS file's own CRC32 is always 2144DF1C: it ends with its CRC)
    print(f"patch  {len(patch):7d} bytes  sha1 {hashlib.sha1(patch).hexdigest()}")
    print(f"OK: {out_p} applies to the source and makes the target")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
