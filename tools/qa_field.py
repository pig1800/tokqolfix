#!/usr/bin/env python3
"""Field-context QA sweep.

Loads tools/lua/town_menu.mss (town field, command menu open), overrides the
next text_show_message index to each message-table index, and captures page 1
with the menu still on screen.  The per-index screen tile set is written into
the report for the compiler's scene reservation.

Assertions mirror tools/qa_sweep.py:
  - page record valid, tiles 0-127;
  - a page tile referenced outside the text window must have been restored
    to kana (otherwise it collides with the menu/HUD);
  - kana inside the window equals bank 9;
  - frame tiles keep their CHR bytes.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import qa_sweep as qs  # noqa: E402

MESEN = Path(r"D:\EMU\NES\Mesen.exe")
BASE_ROM = ROOT / "decomp" / "build" / "rom_kanji.nes"
STATE = ROOT / "tools" / "lua" / "town_menu.mss"
QA = ROOT / "out" / "qa"
ROMS = QA / "field_roms"
SHOTS = QA / "field_shots"
LUA = QA / "field_lua"
RUNS = QA / "field_runs"


def lua_script(index: int, outdir: Path) -> str:
    return f'''local outdir = "{outdir.as_posix()}"
local statepath = "{STATE.as_posix()}"
local qa_index = {index}
local frame = 0
local loaded = false
local started = nil
local overridden = false
local function onExec()
  if loaded then return end
  loaded = true
  local f = assert(io.open(statepath, "rb"))
  local data = f:read("*a"); f:close()
  emu.loadSavestate(data)
  emu.write(0x1E8, 0, emu.memType.nesMemory)
  emu.write(0x1E9, 0, emu.memType.nesMemory)
  emu.write(0x1EA, 0, emu.memType.nesMemory)
  frame = 0
end
local function onInput()
  if not loaded then return end
  if started then
    emu.setInput({{a=false, b=false, start=false, select=false, down=false}}, 0)
    return
  end
  if frame >= 25 and (frame % 30) < 3 then
    emu.setInput({{a=true}}, 0)
  else
    emu.setInput({{a=false}}, 0)
  end
end
local function w(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function onShow()
  if overridden or not loaded then return end
  overridden = true
  emu.write(0x14, qa_index % 256, emu.memType.nesMemory)
  emu.write(0x15, math.floor(qa_index / 256), emu.memType.nesMemory)
end
local function onOverlay()
  if started or not overridden then return end
  started = frame
end
local function dump()
  w("page1.png", emu.takeScreenshot())
  local p = {{}}
  for i = 0, 0x2FFF do p[#p+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
  w("page1_ppu.bin", table.concat(p))
  local c = {{}}
  for i = 0, 0x3FFF do c[#c+1] = string.char(emu.read(i, emu.memType.nesChrRam)) end
  w("page1_chr.bin", table.concat(c))
  local r = {{}}
  for i = 0, 0x7FF do r[#r+1] = string.char(emu.read(i, emu.memType.nesMemory)) end
  w("page1_ram.bin", table.concat(r))
  local l = assert(io.open(outdir .. "/state.txt", "w"))
  l:write(string.format("STARTED %d INDEX %04X OVERRIDE %s\\n", started, qa_index,
    tostring(overridden)))
  l:close()
end
local function onFrame()
  frame = frame + 1
  if started and frame == started + 60 then
    dump()
    emu.stop(0)
  end
  if not started and frame >= 900 then
    local l = assert(io.open(outdir .. "/state.txt", "w"))
    l:write(string.format("NO_START INDEX %04X OVERRIDE %s FRAME %d\\n", qa_index,
      tostring(overridden), frame))
    l:close()
    emu.stop(0)
  end
end
emu.addMemoryCallback(onExec, emu.callbackType.exec, 0xC000, 0xC000, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onShow, emu.callbackType.exec, 0xD124, 0xD124, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onOverlay, emu.callbackType.exec, 0xB800, 0xB800, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
'''


def check_one(index: int, label: str, rom: Path, lua: Path, outdir: Path,
              font: bytes, base: bytes) -> dict:
    if outdir.exists():
        shutil.rmtree(outdir)
    outdir.mkdir(parents=True)
    try:
        subprocess.run([str(MESEN), "--testRunner", str(rom), str(lua)],
                       timeout=90, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return {"index": index, "label": label, "ok": False,
                "failures": ["mesen timeout"]}
    state = outdir / "state.txt"
    text = state.read_text() if state.exists() else "NO_START"
    if text.startswith("NO_START"):
        if qs.message_is_empty(index, base):
            return {"index": index, "label": label, "ok": True,
                    "empty_record": True, "failures": []}
        return {"index": index, "label": label, "ok": False,
                "failures": ["message did not open in field"]}
    try:
        ram = (outdir / "page1_ram.bin").read_bytes()
        ppu = (outdir / "page1_ppu.bin").read_bytes()
        chr_data = (outdir / "page1_chr.bin").read_bytes()
    except FileNotFoundError as exc:
        return {"index": index, "label": label, "ok": False,
                "failures": [f"missing dump: {exc}"]}

    loc = qs.message_locations(index, base)
    if loc is None:
        return {"index": index, "label": label, "ok": False,
                "failures": ["message stub not found"]}
    page_bank, _data_addr, _meta, tiles = loc
    bank = ram[0x131]
    ptr = ram[0x134] | (ram[0x135] << 8)
    failures = []
    if not (18 <= bank <= 22):
        failures.append(f"text bank ${bank:02X} outside 18-22")
    if len(tiles) > 16 * 4:
        failures.append("page 1 has too many entries")
    if any(t >= 128 for t in tiles):
        failures.append("tile >=128 in page 1")

    nametables = [ppu[0x2000:0x2400], ppu[0x2400:0x2800]]
    tile_set = set(tiles)
    box = qs.page_window(nametables, tile_set)
    if box is None:
        failures.append("window frame not found")
        return {"index": index, "label": label, "ok": False,
                "failures": failures, "bank": bank, "ptr": ptr,
                "screen": []}
    screen_set: set[int] = set()
    for nt in nametables:
        for i, t in enumerate(nt):
            if t < 0x80 and not qs.inside(i % 32, i // 32, box):
                screen_set.add(t)
    screen = sorted(screen_set)
    chr_base = 0x1000 if (ram[0xFF] & 0x10) else 0x0000
    # The command-menu window is the only box with a $6D/$6E top edge.
    # A page tile referenced inside it must have been restored to kana.
    for nt in nametables:
        for y in range(30):
            for x in range(25):
                if nt[y * 32 + x] != 0x6D or nt[y * 32 + x + 7] != 0x6E:
                    continue
                for dx in range(8):
                    t = nt[y * 32 + x + dx]
                    if t not in tile_set:
                        continue
                    cur = chr_data[chr_base + t * 16:chr_base + (t + 1) * 16]
                    ref = font[t * 8:(t + 1) * 8] + b"\x00" * 8
                    if cur != ref:
                        failures.append(
                            f"tile ${t:02X} in menu box at {x + dx},{y}")
    for nt in nametables:
        for y in range(30):
            for x in range(32):
                t = nt[y * 32 + x]
                if t in tile_set and not qs.inside(x, y, box):
                    cur = chr_data[chr_base + t * 16:chr_base + (t + 1) * 16]
                    ref = font[t * 8:(t + 1) * 8] + b"\x00" * 8
                    if cur != ref:
                        failures.append(
                            f"tile ${t:02X} outside window at {x},{y}")
    interior = (box[0] + 1, box[1] + 1, box[2] - 1, box[3] - 1)
    for y in range(interior[1], interior[3] + 1):
        for x in range(interior[0], interior[2] + 1):
            t = nametables[0][y * 32 + x]
            if t >= 0x80 or t in qs.FRAME_TILES or t == 0x0A or t in tile_set:
                continue
            cur = chr_data[chr_base + t * 16:chr_base + (t + 1) * 16]
            ref = font[t * 8:(t + 1) * 8] + b"\x00" * 8
            if cur != ref:
                failures.append(f"kana tile ${t:02X} corrupted at {x},{y}")
    present = {nametables[0][i] for i in range(0x400)} | {
        nametables[1][i] for i in range(0x400)}
    for t, want in qs.FRAME_BYTES.items():
        if t in present:
            cur = chr_data[chr_base + t * 16:chr_base + (t + 1) * 16]
            if cur != want:
                failures.append(f"frame tile ${t:02X} changed")
    shot = outdir / "page1.png"
    if shot.exists():
        shutil.copyfile(shot, SHOTS / f"{index:04X}.png")
    return {"index": index, "label": label, "ok": not failures,
            "failures": failures, "bank": bank, "ptr": ptr,
            "entries": len(tiles) // 4, "window": box, "screen": screen}


def ensure_state() -> bool:
    if STATE.exists():
        return True
    save_lua = ROOT / "tools" / "lua" / "town_menu_save.lua"
    if not save_lua.exists():
        return False
    subprocess.run([sys.executable, str(ROOT / "tools" / "mesen_run.py"),
                    str(BASE_ROM), str(save_lua), "--name", "town_menu_state"],
                   timeout=180, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    produced = ROOT / "out" / "test" / "field_state.mss"
    if produced.exists():
        STATE.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(produced, STATE)
        return True
    return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--indices", default=None)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()
    if not ensure_state():
        print(f"missing field save state: {STATE}", file=sys.stderr)
        return 2
    for d in (SHOTS, ROMS, LUA, RUNS):
        d.mkdir(parents=True, exist_ok=True)
    indices = qs.load_indices()
    if args.indices:
        wanted = {int(x, 16) for x in args.indices.split(",")}
        indices = [(v, l) for v, l in indices if v in wanted]
    if args.limit:
        indices = indices[:args.limit]
    font = qs.read_font()
    base = BASE_ROM.read_bytes()

    def task(item: tuple[int, str], worker: int) -> dict:
        index, label = item
        rom = ROMS / f"fq_w{worker}.nes"
        qs.patch_rom(index, rom, base)
        lua = LUA / f"fq_{index:04X}.lua"
        outdir = RUNS / f"{index:04X}"
        lua.write_text(lua_script(index, outdir), encoding="utf-8")
        return check_one(index, label, rom, lua, outdir, font, base)

    results = []
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(task, item, i % args.workers): item
                   for i, item in enumerate(indices)}
        for n, fut in enumerate(as_completed(futures), 1):
            try:
                res = fut.result()
            except Exception as exc:
                index, label = futures[fut]
                res = {"index": index, "label": label, "ok": False,
                       "failures": [f"exception: {exc}"]}
            results.append(res)
            if n % 25 == 0 or not res["ok"]:
                print(f"[{n}/{len(indices)}] {res['index']:04X} "
                      f"{res['label']} {'OK' if res['ok'] else 'FAIL'}")
    results.sort(key=lambda r: r["index"])
    report = {"indices": len(results),
              "empty_records": sum(1 for r in results if r.get("empty_record")),
              "failures": sum(1 for r in results if not r["ok"]),
              "seconds": round(time.time() - t0, 1),
              "results": results}
    (QA / "field_report.json").write_text(json.dumps(report, indent=2),
                                          encoding="utf-8")
    print(json.dumps({k: report[k] for k in
                      ("indices", "empty_records", "failures", "seconds")},
                     indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
