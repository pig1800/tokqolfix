#!/usr/bin/env python3
"""Run tools/lua/garble_check.lua for several input-timing offsets in parallel.

Usage: python tools/garble_run.py <rom> [--tag k] [--offsets 0,7,13] [--frames 6000]
Writes out/test/r12/garble_<tag>_<offset>.txt and prints a summary.
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mesen_run import fresh_battery  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
MESEN = Path(r"D:\EMU\NES\Mesen.exe")
OUT = ROOT / "out" / "test" / "r12"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("rom", type=Path)
    ap.add_argument("--tag", default="k")
    ap.add_argument("--offsets", default="0,3,7,13,21,34")
    ap.add_argument("--frames", type=int, default=6000)
    ap.add_argument("--debug", action="store_true")
    ap.add_argument("--lua", type=Path, default=ROOT / "tools" / "lua" / "garble_check.lua")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    src = args.lua.read_text(encoding="utf-8")
    procs = []
    for off in [int(x) for x in args.offsets.split(",")]:
        s = re.sub(r"local OFF = \d+", f"local OFF = {off}", src)
        s = re.sub(r"local LAST = \d+", f"local LAST = {args.frames}", s)
        s = re.sub(r'local tag = "[^"]*"', f'local tag = "{args.tag}"', s)
        if args.debug:
            s = s.replace("local DEBUG = false", "local DEBUG = true")
        lua = OUT / f"run_{args.tag}_{off}.lua"
        lua.write_text(s, encoding="utf-8")
        rom = OUT / f"g_{args.tag}_{off}.nes"
        fresh_battery(rom.stem)
        shutil.copyfile(args.rom, rom)
        for old in OUT.glob(f"g_{args.tag}_{off}_f*.png"):
            old.unlink()
        procs.append((off, subprocess.Popen([str(MESEN), "--testRunner", str(rom), str(lua)])))
    rc = 0
    for off, p in procs:
        try:
            p.wait(timeout=900)
        except subprocess.TimeoutExpired:
            p.kill()
            print(f"offset {off}: timeout")
            rc = 2
    for off, _ in procs:
        txt = OUT / f"garble_{args.tag}_{off}.txt"
        print(txt.read_text(encoding="utf-8") if txt.exists() else f"offset {off}: no output")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
