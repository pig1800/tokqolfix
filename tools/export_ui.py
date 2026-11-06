#!/usr/bin/env python3
"""Decode the menu/UI strings that live outside the two message banks.

This is a reference extraction: the menu scripts are inline in bank 15 and
in bank 13 code, so they are not part of the editable message build yet.
"""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import textdata

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "decomp" / "text" / "ui_strings.txt"


def main() -> int:
    lines = [
        "# Decoded menu/UI strings outside banks 10/11",
        "# Addresses are CPU addresses; byte lengths include the $FF terminator.",
        "# This file is a reference extraction, not part of the build yet.",
        "",
        "## Bank 13 main-menu strings (pointer table at $90E9)",
    ]
    b13 = textdata.bank_bytes(13)
    ptrs = [b13[0x10E9 + i * 2] | (b13[0x10EA + i * 2] << 8) for i in range(4)]
    for p in ptrs:
        off = p - 0x8000
        end = b13.find(b"\xff", off)
        data = b13[off:end + 1]
        lines.append(f"$ {p:04X} len={len(data):2d}: {textdata.encode_record(data)}")

    lines += ["", "## Bank 15 command menu (inline script at $E94D)"]
    b15 = textdata.bank_bytes(15)
    for a, n, label in [
        (0x294D, 0x1E, "command menu"),
        (0x2978, 0x07, "yes/no"),
        (0x298C, 0x08, "formation/strategist"),
    ]:
        data = b15[a:a + n]
        lines.append(f"$ {0xC000 + a:04X}: {textdata.encode_record(data)}")

    lines += ["", "## Bank 15 speed menu and confirmation (inline script at $ED50)"]
    for a, n, label in [
        (0x2D50, 0x0C, "speed"),
        (0x2D60, 0x07, "yes/no"),
    ]:
        data = b15[a:a + n]
        lines.append(f"$ {0xC000 + a:04X}: {textdata.encode_record(data)}")

    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
