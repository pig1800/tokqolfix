#!/usr/bin/env python3
"""Patch upload_glyph to RTS in every text bank for the scene-borrow survey.

The survey must see the original scene CHR at the first glyph upload.  With
upload_glyph patched out, the text misses its kanji glyphs but the scene and
font tiles are never modified, so every message opens in a clean scene.

Usage:
    python tools/make_survey_rom.py
    python tools/mesen_run.py out/test/survey_noupload.nes \
        tools/lua/scene_borrow_kanji.lua --name borrow
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROM = ROOT / "decomp" / "build" / "rom_kanji.nes"
HOOKS = ROOT / "decomp" / "build" / "kanji" / "fixed_hooks.inc"
OUT = ROOT / "out" / "test" / "survey_noupload.nes"
TEXT_BANKS = range(18, 23)


def main() -> int:
    labels = {}
    for line in HOOKS.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^(RAM_\w+)\s*=\s*\$([0-9A-Fa-f]+)$", line.strip())
        if m:
            labels[m.group(1)] = int(m.group(2), 16)
    upload = labels["RAM_UPLOAD_GLYPH"]
    if not (0xB800 <= upload < 0xC000):
        raise SystemExit(f"upload_glyph address ${upload:04X} is outside the overlay")
    rom = bytearray(ROM.read_bytes())
    for bank in TEXT_BANKS:
        off = 16 + bank * 0x4000 + (upload - 0x8000)
        rom[off] = 0x60  # RTS
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(rom)
    print(f"patched upload_glyph ${upload:04X} to RTS in banks "
          f"{TEXT_BANKS.start}-{TEXT_BANKS.stop - 1}: {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
