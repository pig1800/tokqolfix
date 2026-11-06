#!/usr/bin/env python3
"""Headless Mesen helper for the kanji target.

Usage:
    python tools/mesen_run.py <rom> <lua> [--timeout seconds]

The ROM is copied under out/test so Mesen's battery-save key never touches
the real game save.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MESEN = Path(r"D:\EMU\NES\Mesen.exe")
RUN_DIR = ROOT / "out" / "test"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("rom", type=Path)
    ap.add_argument("lua", type=Path)
    ap.add_argument("--name", default=None)
    ap.add_argument("--timeout", type=int, default=120)
    args = ap.parse_args()

    RUN_DIR.mkdir(parents=True, exist_ok=True)
    name = args.name or args.rom.stem
    rom_copy = RUN_DIR / f"{name}.nes"
    shutil.copyfile(args.rom, rom_copy)
    lua = args.lua.resolve()

    cmd = [str(MESEN), "--testRunner", str(rom_copy), str(lua)]
    print(" ".join(cmd))
    try:
        proc = subprocess.run(cmd, timeout=args.timeout)
    except subprocess.TimeoutExpired:
        print("Mesen timed out", file=sys.stderr)
        return 2
    print(f"exit={proc.returncode}")
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
