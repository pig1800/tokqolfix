#!/usr/bin/env python3
"""Build the 512 KiB kanji-target resources.

Owns the bank-31 fixed-bank mirror, the bank-13 far-text trampoline, the
font banks and the generated text/metadata banks.  The original 256 KiB
target never runs this script.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROM = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
OUT = ROOT / "decomp" / "build" / "kanji"
ASM = ROOT / "tools" / "asm"
ASM6F = ROOT / "tools" / "toolchain" / "asm6f" / "asm6f_64.exe"

# Text-engine patches in the fixed-bank copy (bank 31).
def overlay_labels(listing: Path) -> dict[str, int]:
    labels: dict[str, int] = {}
    for line in listing.read_text(encoding="utf-8", errors="ignore").splitlines():
        m = re.match(r"^0([0-9A-Fa-f]{4})\s+([A-Za-z_][A-Za-z0-9_]*):", line)
        if m:
            labels[m.group(2)] = int(m.group(1), 16)
    return labels


def build_patches(listing: Path) -> list[tuple[int, bytes]]:
    l = overlay_labels(listing)
    return [
        (0xD28E, bytes((0x4C, l["text_dispatch"] & 0xFF, l["text_dispatch"] >> 8))),
        (0xD2BB, bytes((0x20, l["kana_prepare"] & 0xFF, l["kana_prepare"] >> 8))),
        (0xD2C7, bytes((0x20, l["ctrl_store"] & 0xFF, l["ctrl_store"] >> 8))),
        (0xEECB, bytes((0x20, l["nmi_hook"] & 0xFF, l["nmi_hook"] >> 8))),
        (0xEE7F, bytes((0x4C, l["nmi_entry"] & 0xFF, l["nmi_entry"] >> 8))),
    ]



def prg() -> bytes:
    return ROM.read_bytes()[16:]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def write_bank(name: str, data: bytes) -> None:
    assert len(data) == 0x4000, (name, len(data))
    (OUT / name).write_bytes(data)


def assemble(name: str) -> bytes:
    src = ASM / f"{name}.asm"
    dst = OUT / f"{name}.bin"
    lst = OUT / f"{name}.lst"
    cmd = [str(ASM6F), str(src), str(dst), "-l", str(lst)]
    result = subprocess.run(cmd, cwd=ASM, text=True, capture_output=True)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode != 0:
        raise SystemExit(f"assembly failed: {name}")
    return dst.read_bytes()


def build_font() -> None:
    sys.path.insert(0, str(ROOT / "tools"))
    import kanji_font
    kanji_font.build()
    font = (OUT / "kanji_font.bin").read_bytes()
    bank16 = bytearray(0x4000)
    bank17 = bytearray(0x4000)
    first = min(len(font), 0x4000)
    bank16[:first] = font[:first]
    if len(font) > 0x4000:
        second = min(len(font) - 0x4000, 0x4000)
        bank17[:second] = font[0x4000:0x4000 + second]
    write_bank("bank16.bin", bytes(bank16))
    write_bank("bank17.bin", bytes(bank17))


def build_text() -> None:
    sys.path.insert(0, str(ROOT / "tools"))
    import kanji_text
    kanji_text.build()


def build_far_head(far_block: bytes) -> None:
    original = prg()
    head = bytearray(original[13 * 0x4000:13 * 0x4000 + 0x800])
    assert far_block
    assert len(far_block) <= 255, len(far_block)
    block = far_block + bytes(0x60 for _ in range(255 - len(far_block)))
    entry = 0x0317
    head[entry:entry + 3] = bytes((0x20, 0xE4, 0xC4))  # jsr call_inline_block
    head[entry + 3:entry + 3 + 255] = block
    (OUT / "bank13_head.bin").write_bytes(bytes(head))


def build_bank15(switcher: bytes) -> None:
    original = prg()
    bank = bytearray(original[15 * 0x4000:16 * 0x4000])
    # Redirect the original 20-byte PRG-only switcher to the SUROM routine in
    # the unused C611..C676 gap.
    off = 0xC4B7 - 0xC000
    bank[off:off + 3] = bytes((0x4C, 0x11, 0xC6))
    off = 0xC611 - 0xC000
    bank[off:off + len(switcher)] = switcher
    write_bank("bank15.bin", bytes(bank))


def build_bank31(overlay: bytes, patches: list[tuple[int, bytes]]) -> None:
    bank = bytearray((OUT / "bank15.bin").read_bytes())
    for addr, data in patches:
        off = addr - 0xC000
        bank[off:off + len(data)] = data
    # Overlay lives in the unused $E000 data block.
    off = 0xE000 - 0xC000
    assert off + len(overlay) <= 0x4000
    bank[off:off + len(overlay)] = overlay
    write_bank("bank31.bin", bytes(bank))


def build_skeleton() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    blank = bytes(0x4000)
    for bank in range(24, 31):
        write_bank(f"bank{bank:02d}.bin", blank)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["build"], nargs="?", default="build")
    ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    fixed = assemble("kanji_fixed")
    far = assemble("kanji_far")
    switcher = assemble("surom_b15")
    build_font()
    build_text()
    build_far_head(far)
    build_bank15(switcher)
    build_bank31(fixed, build_patches(OUT / "kanji_fixed.lst"))
    build_skeleton()
    print(f"fixed overlay: {len(fixed)} bytes; far block: {len(far)} bytes")
    print(f"wrote kanji resources to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
