#!/usr/bin/env python3
"""Warp the history prompt to each message and run a page-1 QA pass.

The history menu calls text_print_inline with an inline message index at
bank 13 $8B58 / $8BDA / $8C38.  Patching those words to index N makes the
title-screen history prompt render message N.  One Mesen run per index, four
workers in parallel.

For now the sweep captures page 1 and asserts:
  - the page record is valid and its tiles are 0-127;
  - no page tile appears in either nametable outside the window box;
  - every kana tile inside the window still equals the bank-9 glyph;
  - the window frame tiles keep their original CHR bytes.

Results: out/qa/report.json and out/qa/shots/<index>.png
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MESEN = Path(r"D:\EMU\NES\Mesen.exe")
BASE_ROM = ROOT / "decomp" / "build" / "rom_kanji.nes"
ORIGINAL = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
INDEX_SYMBOLS = ROOT / "decomp" / "build" / "text" / "index_symbols.inc"
QA = ROOT / "out" / "qa"
ROMS = QA / "roms"
SHOTS = QA / "shots"
LUA = QA / "lua"
RUNS = QA / "runs"
PATCH_SITES = (0x8B58, 0x8BDA, 0x8C38)
FRAME_TILES = {0x0B, 0x0D, 0x6D, 0x6E, 0x6F, 0x7D, 0x7E}
FRAME_BYTES = {
    0x0B: bytes.fromhex("60606060607f3f000000000000000000"),
    0x0C: bytes.fromhex("00ffff00000000000000000000000000"),
    0x0D: bytes.fromhex("0000000000ffff000000000000000000"),
    0x6D: bytes.fromhex("003f7f60606060600000000000000000"),
    0x6E: bytes.fromhex("00fcfe06060606060000000000000000"),
    0x6F: bytes.fromhex("0606060606fefc000000000000000000"),
    0x7D: bytes.fromhex("60606060606060600000000000000000"),
    0x7E: bytes.fromhex("06060606060606060000000000000000"),
}


def read_font() -> bytes:
    rom = ORIGINAL.read_bytes()
    return rom[16 + 9 * 0x4000 + 0x3A00:16 + 9 * 0x4000 + 0x3E00]


def load_indices() -> list[tuple[int, str]]:
    out = []
    for line in INDEX_SYMBOLS.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^(b1[01]_msg_index_\d+)\s*=\s*\$([0-9A-Fa-f]+)$", line.strip())
        if m:
            out.append((int(m.group(2), 16), m.group(1)))
    return sorted(out)


def message_locations(index: int, base: bytes) -> tuple[int, int, int, list[int]] | None:
    """Return (text bank, data addr, meta addr, page-1 tiles) for an index."""
    bank = 10 if index < 0x200 else 11
    table_index = index if bank == 10 else index - 0x200
    off = 16 + bank * 0x4000
    stub = base[off + table_index] | (base[off + 0x200 + table_index] << 8)
    so = off + (stub - 0x8000)
    if base[so:so + 3] != b"\xF8\x3A\xC6":
        return None
    text_bank = base[so + 3]
    data_addr = base[so + 4] | (base[so + 5] << 8)
    meta = base[so + 6] | (base[so + 7] << 8)
    mo = 16 + text_bank * 0x4000 + (meta - 0x8000)
    count = base[mo + 1]
    tiles: list[int] = []
    if count <= 16:
        for i in range(count):
            eo = mo + 2 + i * 6
            tiles.extend(base[eo + 2:eo + 6])
    return (text_bank, data_addr, meta, tiles)


def patch_rom(index: int, dst: Path, base: bytes) -> None:
    data = bytearray(base)
    for addr in PATCH_SITES:
        off = 16 + 13 * 0x4000 + (addr - 0x8000)
        data[off] = index & 0xFF
        data[off + 1] = index >> 8
    loc = message_locations(index, base)
    if loc is not None:
        text_bank, data_addr, _meta, _tiles = loc
        data_off = 16 + text_bank * 0x4000 + (data_addr - 0x8000)
        # Keep the warp rendering page 1: turn the first page break into a
        # WAIT so the page-1 text stays on screen for the assertion dump.
        end = data_off
        while end < len(data) and data[end] != 0xFF:
            if data[end] == 0xFC:
                data[end] = 0xFD
                if end + 1 < len(data):
                    data[end + 1] = 0xFF
                break
            end += 1
    dst.write_bytes(data)


def lua_script(index: int, outdir: Path) -> str:
    return f'''local outdir = "{outdir.as_posix()}"
local frame = 0
local started = nil
local function onInput()
  if frame >= 880 and frame <= 900 then
    emu.setInput({{start=false, a=false, b=false, select=false, down=false}}, 0)
    return
  end
  if started then
    emu.setInput({{a = false}}, 0)
    return
  end
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({{start=true}}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then
    emu.setInput({{a=true}}, 0)
  elseif frame >= 800 and frame < 2000 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({{start=true}}, 0)
    elseif phase == 2 then emu.setInput({{a=true}}, 0)
    elseif phase == 4 then emu.setInput({{down=true}}, 0)
    else emu.setInput({{start=false, a=false, b=false, select=false, down=false}}, 0)
    end
  else
    emu.setInput({{start=false, a=false, b=false, select=false, down=false}}, 0)
  end
end
local function w(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function onOverlay()
  if started or frame < 800 then return end
  started = frame
end
local function onFrame()
  frame = frame + 1
  if started and frame == started + 180 then
    w("page1.png", emu.takeScreenshot())
    local p = {{}}
    for i = 0, 0x2FFF do p[#p+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
    w("page1_ppu.bin", table.concat(p))
    local c = {{}}
    for i = 0, 0x1FFF do c[#c+1] = string.char(emu.read(i, emu.memType.nesChrRam)) end
    w("page1_chr.bin", table.concat(c))
    local r = {{}}
    for i = 0, 0x7FF do r[#r+1] = string.char(emu.read(i, emu.memType.nesMemory)) end
    w("page1_ram.bin", table.concat(r))
    local l = assert(io.open(outdir .. "/state.txt", "w"))
    l:write(string.format("STARTED %d\\n", started))
    l:close()
    emu.stop(0)
  end
  if frame == 2400 and not started then
    local l = assert(io.open(outdir .. "/state.txt", "w"))
    l:write("NO_START\\n")
    l:close()
    emu.stop(0)
  end
end
emu.addMemoryCallback(onOverlay, emu.callbackType.exec, 0xB800, 0xB800, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
'''


def window_box(nametables: list[bytes]) -> tuple[int, int, int, int] | None:
    rows = []
    cols = []
    for nt in nametables:
        for y in range(30):
            for x in range(32):
                if nt[y * 32 + x] in FRAME_TILES:
                    rows.append(y)
                    cols.append(x)
    if not rows:
        return None
    return min(cols), min(rows), max(cols), max(rows)


def inside(x: int, y: int, box: tuple[int, int, int, int]) -> bool:
    x0, y0, x1, y1 = box
    return x0 <= x <= x1 and y0 <= y <= y1


def first_page_for(index: int, base: bytes) -> tuple[int, int, list[int]] | None:
    """Resolve index -> (text bank, entry count, tile numbers) for page 1."""
    bank = 10 if index < 0x200 else 11
    table_index = index if bank == 10 else index - 0x200
    off = 16 + bank * 0x4000
    stub = base[off + table_index] | (base[off + 0x200 + table_index] << 8)
    so = off + (stub - 0x8000)
    if base[so:so + 3] != b"\xF8\x3A\xC6":
        return None
    text_bank = base[so + 3]
    meta = base[so + 6] | (base[so + 7] << 8)
    mo = 16 + text_bank * 0x4000 + (meta - 0x8000)
    count = base[mo + 1]
    if count > 16:
        return (text_bank, count, [])
    tiles = []
    for i in range(count):
        eo = mo + 2 + i * 6
        tiles.extend(base[eo + 2:eo + 6])
    return (text_bank, count, tiles)


def check_one(index: int, label: str, rom: Path, lua: Path, outdir: Path,
              font: bytes, base: bytes) -> dict:
    if outdir.exists():
        shutil.rmtree(outdir)
    outdir.mkdir(parents=True)
    save = Path(r"D:\EMU\NES\Saves") / f"{rom.stem}.sav"
    if save.exists():
        save.unlink()
    try:
        subprocess.run([str(MESEN), "--testRunner", str(rom), str(lua)],
                       timeout=90, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return {"index": index, "label": label, "ok": False,
                "failures": ["mesen timeout"]}
    state = outdir / "state.txt"
    if not state.exists() or state.read_text().startswith("NO_START"):
        return {"index": index, "label": label, "ok": False,
                "failures": ["message did not open"]}
    try:
        ram = (outdir / "page1_ram.bin").read_bytes()
        ppu = (outdir / "page1_ppu.bin").read_bytes()
        chr_data = (outdir / "page1_chr.bin").read_bytes()
    except FileNotFoundError as exc:
        return {"index": index, "label": label, "ok": False,
                "failures": [f"missing dump: {exc}"]}

    first = first_page_for(index, base)
    if first is None:
        return {"index": index, "label": label, "ok": False,
                "failures": ["message stub not found"]}
    page_bank, count, tiles = first
    bank = ram[0x131]
    ptr = ram[0x134] | (ram[0x135] << 8)
    pages_left = ram[0x138]
    failures = []
    if not (18 <= bank <= 22):
        failures.append(f"text bank ${bank:02X} outside 18-22")
    if count > 16:
        failures.append(f"page count {count} > 16")
    if any(t >= 128 for t in tiles):
        failures.append("tile >=128 in page 1")
    no_kanji = not tiles
    nametables = [ppu[0x2000:0x2400], ppu[0x2400:0x2800]]
    box = window_box(nametables)
    if box is None:
        failures.append("window frame not found")
        return {"index": index, "label": label, "ok": False,
                "failures": failures, "bank": bank, "ptr": ptr}
    # (a) page tiles must not appear outside the window box
    tile_set = set(tiles)
    for nt in nametables:
        for y in range(30):
            for x in range(32):
                if nt[y * 32 + x] in tile_set and not inside(x, y, box):
                    failures.append(
                        f"tile ${nt[y * 32 + x]:02X} outside window at {x},{y}")
    # (b) kana inside the window must match the bank-9 glyph
    chr_base = 0x1000 if (ram[0xFF] & 0x10) else 0x0000
    interior = (box[0] + 1, box[1] + 1, box[2] - 1, box[3] - 1)
    for y in range(interior[1], interior[3] + 1):
        for x in range(interior[0], interior[2] + 1):
            t = nametables[0][y * 32 + x]
            if t >= 0x80 or t in FRAME_TILES or t == 0x0A or t in tile_set:
                continue
            cur = chr_data[chr_base + t * 16:chr_base + (t + 1) * 16]
            ref = font[t * 8:(t + 1) * 8] + b"\x00" * 8
            if cur != ref:
                failures.append(f"kana tile ${t:02X} corrupted at {x},{y}")
    # (c) frame tiles keep their original CHR bytes
    present = {nametables[0][i] for i in range(0x400)} | {
        nametables[1][i] for i in range(0x400)}
    for t, want in FRAME_BYTES.items():
        if t in present:
            cur = chr_data[chr_base + t * 16:chr_base + (t + 1) * 16]
            if cur != want:
                failures.append(f"frame tile ${t:02X} changed")
    # save a screenshot
    shot = outdir / "page1.png"
    if shot.exists():
        shutil.copyfile(shot, SHOTS / f"{index:04X}.png")
    return {"index": index, "label": label, "ok": not failures,
            "failures": failures, "bank": bank, "ptr": ptr,
            "pages_left": pages_left, "entries": count,
            "window": box}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--indices", default=None,
                    help="comma separated hex values; default all")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    QA.mkdir(parents=True, exist_ok=True)
    SHOTS.mkdir(parents=True, exist_ok=True)
    ROMS.mkdir(parents=True, exist_ok=True)
    LUA.mkdir(parents=True, exist_ok=True)
    RUNS.mkdir(parents=True, exist_ok=True)
    if not BASE_ROM.exists():
        print("missing kanji ROM", file=sys.stderr)
        return 2
    indices = load_indices()
    if args.indices:
        wanted = {int(x, 16) for x in args.indices.split(",")}
        indices = [(v, l) for v, l in indices if v in wanted]
    if args.limit:
        indices = indices[:args.limit]
    font = read_font()
    base = BASE_ROM.read_bytes()

    def task(item: tuple[int, str], worker: int) -> dict:
        index, label = item
        rom = ROMS / f"qa_w{worker}.nes"
        patch_rom(index, rom, base)
        lua = LUA / f"qa_{index:04X}.lua"
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
    report = {
        "indices": len(results),
        "failures": sum(1 for r in results if not r["ok"]),
        "seconds": round(time.time() - t0, 1),
        "results": results,
    }
    (QA / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({k: report[k] for k in ("indices", "failures", "seconds")},
                     indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
