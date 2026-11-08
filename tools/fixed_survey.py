#!/usr/bin/env python3
"""Check the candidate fixed-bank gaps on the history-prompt QA sweep.

Runs the original ROM with the history warp patch and a read/exec watch on
the candidate ranges.  Results: out/test/fixedsurvey/sweep.txt
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MESEN = Path(r"D:\EMU\NES\Mesen.exe")
ORIGINAL = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
OUT = ROOT / "out" / "test" / "fixedsurvey"
ROMS = OUT / "roms"
LUA = OUT / "lua"
RUNS = OUT / "runs"
PATCH_SITES = (0x8B58, 0x8BDA, 0x8C38)
RANGES = ((0xC4BA, 0xC4CA), (0xE6B3, 0xE6C3), (0xFFE0, 0xFFEF))

SCRIPT = '''local outdir = "{outdir}"
local frame = 0
local hits = {{}}
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({{start=true}}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({{a=true}}, 0)
  elseif frame >= 800 and frame < 2000 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({{start=true}}, 0)
    elseif phase == 2 then emu.setInput({{a=true}}, 0)
    elseif phase == 4 then emu.setInput({{down=true}}, 0)
    else emu.setInput({{start=false, a=false, b=false, select=false, down=false}}, 0) end
  else emu.setInput({{start=false, a=false, b=false, select=false, down=false}}, 0) end
end
local function onHit(addr) hits[addr] = (hits[addr] or 0) + 1 end
local function onFrame()
  frame = frame + 1
  if frame == 2000 then
    local f = assert(io.open(outdir .. "/hits.txt", "w"))
    for a = {lo}, {hi} do
      if hits[a] then f:write(string.format("%04X %d\\n", a, hits[a])) end
    end
    f:close(); emu.stop(0)
  end
end
for _, r in ipairs({{{ranges}}}) do
  emu.addMemoryCallback(onHit, emu.callbackType.read, r[1], r[2], emu.memType.nesMemory, emu.cpuType.nes)
  emu.addMemoryCallback(onHit, emu.callbackType.exec, r[1], r[2], emu.memType.nesMemory, emu.cpuType.nes)
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
'''


def load_indices() -> list[int]:
    text = (ROOT / "decomp" / "build" / "text" / "index_symbols.inc").read_text(encoding="utf-8")
    out = []
    for line in text.splitlines():
        m = re.match(r"^b1[01]_msg_index_\d+\s*=\s*\$([0-9A-Fa-f]+)$", line.strip())
        if m:
            out.append(int(m.group(1), 16))
    return sorted(out)


def main() -> int:
    step = int(sys.argv[1]) if len(sys.argv) > 1 else 16
    base = bytearray(ORIGINAL.read_bytes())
    indices = load_indices()[::step]
    OUT.mkdir(parents=True, exist_ok=True)
    ROMS.mkdir(exist_ok=True)
    LUA.mkdir(exist_ok=True)
    RUNS.mkdir(exist_ok=True)
    def task(index: int) -> dict[int, int]:
        data = bytearray(base)
        for addr in PATCH_SITES:
            off = 16 + 13 * 0x4000 + (addr - 0x8000)
            data[off] = index & 0xFF
            data[off + 1] = index >> 8
        rom = ROMS / f"sw_{index:04X}.nes"
        rom.write_bytes(data)
        outdir = RUNS / f"{index:04X}"
        if outdir.exists():
            shutil.rmtree(outdir)
        outdir.mkdir()
        lua = LUA / f"{index:04X}.lua"
        ranges = ", ".join(f"{{{lo:04X}, {hi:04X}}}" for lo, hi in RANGES)
        lua.write_text(SCRIPT.format(outdir=outdir.as_posix(), lo=RANGES[0][0],
                                     hi=RANGES[-1][1], ranges=ranges), encoding="utf-8")
        save = Path(r"D:\EMU\NES\Saves") / f"{rom.stem}.sav"
        if save.exists():
            save.unlink()
        try:
            subprocess.run([str(MESEN), "--testRunner", str(rom), str(lua)],
                           timeout=60, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
        except subprocess.TimeoutExpired:
            return {}
        hits: dict[int, int] = {}
        p = outdir / "hits.txt"
        if p.exists():
            for line in p.read_text().splitlines():
                a, n = line.split()
                hits[int(a, 16)] = int(n)
        return hits

    total: dict[int, int] = {}
    for hits in ThreadPoolExecutor(max_workers=4).map(task, indices):
        for a, n in hits.items():
            total[a] = total.get(a, 0) + n
    lines = [f"indices {len(indices)} (step {step})"]
    for lo, hi in RANGES:
        got = {a: total[a] for a in range(lo, hi + 1) if a in total}
        lines.append(f"{lo:04X}-{hi:04X}: {len(got)} touched bytes; {got}")
    (OUT / "sweep.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
