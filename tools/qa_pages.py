#!/usr/bin/env python3
"""Per-page QA sweep.

The text engine auto-advances pages as it types; this harness samples every
5 frames, groups samples by KANJI_PAGE_PTR, keeps the most-drawn sample for
each page record, and asserts per page:
  - page record valid, tiles 0-127;
  - a page tile referenced outside the text window must have been restored
    to kana;
  - kana inside the window equals bank 9;
  - frame tiles keep their CHR bytes.
Tiles from earlier pages that can still be visible are treated as page tiles.
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
QA = ROOT / "out" / "qa"
ROMS = QA / "page_roms"
SHOTS = QA / "page_shots"
LUA = QA / "page_lua"
RUNS = QA / "page_runs"
PATCH_SITES = qs.PATCH_SITES
SAMPLE_EVERY = 2


def message_data_span(index: int, base: bytes) -> tuple[int, int] | None:
    loc = qs.message_locations(index, base)
    if loc is None:
        return None
    text_bank, data_addr, _meta, _tiles = loc
    off = 16 + text_bank * 0x4000 + (data_addr - 0x8000)
    pos = off
    while pos < len(base):
        b = base[pos]
        if 0xEC <= b <= 0xEE:
            pos += 2
            continue
        if b in (0xEF, 0xF0, 0xF1, 0xF2):
            pos += 2
            continue
        if b in (0xF8, 0xF9):
            pos += 3
            continue
        if b == 0xFF:
            return off, pos
        pos += 1
    return off, len(base) - 1


def page_records(index: int, base: bytes) -> list[tuple[int, list[int]]]:
    """Return [(page pointer, tile numbers)] for every page."""
    loc = qs.message_locations(index, base)
    if loc is None:
        return []
    text_bank, _data_addr, meta, _tiles = loc
    bank_off = 16 + text_bank * 0x4000
    off = bank_off + (meta - 0x8000)
    count = base[off]
    pos = off + 1
    records = []
    for _ in range(count):
        if pos >= off + 0x1000:
            break
        ptr = 0x8000 + (pos - bank_off)
        n = base[pos]
        tiles = []
        for i in range(min(n, 16)):
            tiles.extend(base[pos + 1 + i * 6 + 2:pos + 1 + i * 6 + 6])
        records.append((ptr, tiles))
        pos += 1 + 6 * n
    return records


def patch_rom(index: int, dst: Path, base: bytes) -> None:
    data = bytearray(base)
    for addr in PATCH_SITES:
        off = 16 + 13 * 0x4000 + (addr - 0x8000)
        data[off] = index & 0xFF
        data[off + 1] = index >> 8
    span = message_data_span(index, base)
    if span is not None:
        start, end = span
        pos = start
        while pos <= end and pos < len(data):
            b = data[pos]
            if 0xEC <= b <= 0xEE:
                pos += 2
                continue
            if b in (0xEF, 0xF0, 0xF1, 0xF2):
                pos += 2
                continue
            if b == 0xF8:
                data[pos:pos + 3] = b"\x0A\x0A\x0A"
                pos += 3
                continue
            if b == 0xF9:       # JUMP: keep the first message
                data[pos] = 0xFF
                break
            pos += 1
    dst.write_bytes(data)


def lua_script(index: int, outdir: Path) -> str:
    return f'''local outdir = "{outdir.as_posix()}"
local frame = 0
local started = nil
local overridden = false
local last_ptr = nil
local last_change = 0
local log = assert(io.open(outdir .. "/index.txt", "w"))
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) == 0 then
    emu.setInput({{start=true}}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) == 0 then
    emu.setInput({{a=true}}, 0)
  elseif not started and frame >= 800 and frame < 2000 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 and (frame % 40) == 0 then emu.setInput({{start=true}}, 0)
    elseif phase == 2 and (frame % 40) == 2 then emu.setInput({{a=true}}, 0)
    elseif phase == 4 and (frame % 40) == 4 then emu.setInput({{down=true}}, 0)
    else emu.setInput({{start=false, a=false, b=false, select=false, down=false}}, 0)
    end
  elseif started then
    if frame > started + 240 and (frame % 60) == 0 then emu.setInput({{a=true}}, 0)
    else emu.setInput({{a=false}}, 0) end
  else
    emu.setInput({{start=false, a=false, b=false, select=false, down=false}}, 0)
  end
end
local function w(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function onShow()
  if overridden then return end
  overridden = true
  emu.write(0x14, {index} % 256, emu.memType.nesMemory)
  emu.write(0x15, math.floor({index} / 256), emu.memType.nesMemory)
end
local function onOverlay()
  if started then return end
  started = frame
  last_ptr = emu.read(0x134, emu.memType.nesMemory) | (emu.read(0x135, emu.memType.nesMemory) << 8)
  last_change = frame
end
local function dump()
  local tag = string.format("f%04d", frame)
  w(tag .. ".png", emu.takeScreenshot())
  local p = {{}}
  for i = 0, 0x2FFF do p[#p+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
  w(tag .. "_ppu.bin", table.concat(p))
  local c = {{}}
  for i = 0, 0x1FFF do c[#c+1] = string.char(emu.read(i, emu.memType.nesChrRam)) end
  w(tag .. "_chr.bin", table.concat(c))
  local r = {{}}
  for i = 0, 0x7FF do r[#r+1] = string.char(emu.read(i, emu.memType.nesMemory)) end
  w(tag .. "_ram.bin", table.concat(r))
  log:write(string.format("f=%d ptr=%04X line=%02X col=%02X\\n", frame,
    emu.read(0x134, emu.memType.nesMemory) | (emu.read(0x135, emu.memType.nesMemory) << 8),
    emu.read(0x56, emu.memType.nesMemory), emu.read(0x53, emu.memType.nesMemory)))
end
local function onFrame()
  frame = frame + 1
  if not started then
    if frame >= 2400 then
      local l = assert(io.open(outdir .. "/state.txt", "w")); l:write("NO_START\\n"); l:close()
      log:close(); emu.stop(0)
    end
    return
  end
  local ptr = emu.read(0x134, emu.memType.nesMemory) | (emu.read(0x135, emu.memType.nesMemory) << 8)
  if ptr ~= last_ptr then
    last_ptr = ptr
    last_change = frame
  end
  if frame % {SAMPLE_EVERY} == 0 and frame >= started + 2 then dump() end
  if frame - last_change > 360 and frame > started + 400 then log:close(); emu.stop(0) end
  if frame > started + 1800 then log:close(); emu.stop(0) end
end
emu.addMemoryCallback(onShow, emu.callbackType.exec, 0xD124, 0xD124, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onOverlay, emu.callbackType.exec, 0xB800, 0xB800, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
'''


def sample_has_page(outdir: Path, tag: str, tiles: set[int]) -> bool:
    ppu_path = outdir / f"{tag}_ppu.bin"
    if not ppu_path.exists():
        return False
    ppu = ppu_path.read_bytes()
    for base in (0x2000, 0x2400):
        nt = ppu[base:base + 0x400]
        if any(t in tiles for t in nt):
            return True
    return False


def check_page(index: int, label: str, outdir: Path, tag: str, page_index: int,
               visible_tiles: set[int], font: bytes) -> dict:
    try:
        ram = (outdir / f"{tag}_ram.bin").read_bytes()
        ppu = (outdir / f"{tag}_ppu.bin").read_bytes()
        chr_data = (outdir / f"{tag}_chr.bin").read_bytes()
    except FileNotFoundError as exc:
        return {"page": page_index, "ok": False, "failures": [f"missing dump: {exc}"]}
    failures = []
    nametables = [ppu[0x2000:0x2400], ppu[0x2400:0x2800]]
    box = qs.page_window(nametables, visible_tiles)
    if box is None:
        failures.append("window frame not found")
        return {"page": page_index, "ok": False, "failures": failures,
                "screen": []}
    screen_set: set[int] = set()
    for nt in nametables:
        for i, t in enumerate(nt):
            if t < 0x80 and not qs.inside(i % 32, i // 32, box):
                screen_set.add(t)
    screen = sorted(screen_set)
    chr_base = 0x1000 if (ram[0xFF] & 0x10) else 0x0000
    for nt in nametables:
        for y in range(30):
            for x in range(32):
                t = nt[y * 32 + x]
                if t in visible_tiles and not qs.inside(x, y, box):
                    cur = chr_data[chr_base + t * 16:chr_base + (t + 1) * 16]
                    ref = font[t * 8:(t + 1) * 8] + b"\x00" * 8
                    if cur != ref:
                        failures.append(
                            f"tile ${t:02X} outside window at {x},{y}")
    interior = (box[0] + 1, box[1] + 1, box[2] - 1, box[3] - 1)
    for y in range(interior[1], interior[3] + 1):
        for x in range(interior[0], interior[2] + 1):
            t = nametables[0][y * 32 + x]
            if t >= 0x80 or t in qs.FRAME_TILES or t == 0x0A or t in visible_tiles:
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
    shot = outdir / f"{tag}.png"
    if shot.exists():
        shutil.copyfile(shot, SHOTS / f"{index:04X}_p{page_index}.png")
    return {"page": page_index, "ok": not failures, "failures": failures,
            "screen": screen}


def check_one(index: int, label: str, rom: Path, lua: Path,
              outdir: Path, font: bytes) -> dict:
    if outdir.exists():
        shutil.rmtree(outdir)
    outdir.mkdir(parents=True)
    try:
        subprocess.run([str(MESEN), "--testRunner", str(rom), str(lua)],
                       timeout=180, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return {"index": index, "label": label, "ok": False,
                "failures": ["mesen timeout"]}
    state = outdir / "state.txt"
    if state.exists() and state.read_text().startswith("NO_START"):
        if qs.message_is_empty(index, BASE_ROM.read_bytes()):
            return {"index": index, "label": label, "ok": True,
                    "empty_record": True, "failures": [], "pages": []}
        return {"index": index, "label": label, "ok": False,
                "failures": ["message did not open"]}
    base = BASE_ROM.read_bytes()
    records = page_records(index, base)
    if not records:
        return {"index": index, "label": label, "ok": False,
                "failures": ["no page records"], "pages": []}
    ptrs = {ptr: i for i, (ptr, _tiles) in enumerate(records)}
    samples: dict[int, list[tuple[int, int, str]]] = {}
    all_tags: list[str] = []
    ref_cache: dict[str, set[int]] = {}

    def referenced(tag: str) -> set[int]:
        if tag not in ref_cache:
            ppu = (outdir / f"{tag}_ppu.bin").read_bytes()
            used: set[int] = set()
            for base in (0x2000, 0x2400):
                used.update(ppu[base:base + 0x400])
            ref_cache[tag] = used
        return ref_cache[tag]
    log_path = outdir / "index.txt"
    if log_path.exists():
        for line in log_path.read_text().splitlines():
            fields = dict(part.split("=") for part in line.split())
            tag = f"f{int(fields['f']):04d}"
            all_tags.append(tag)
            ptr = int(fields["ptr"], 16)
            if ptr not in ptrs:
                continue
            page_index = ptrs[ptr]
            progress = int(fields["line"], 16) * 256 + int(fields["col"], 16)
            samples.setdefault(page_index, []).append(
                (progress, int(fields["f"]), tag))
    pages = []
    visible: set[int] = set()
    for page_index in range(len(records)):
        visible |= set(records[page_index][1])
        group = samples.get(page_index)
        page_tiles = set(records[page_index][1])
        candidate = None
        if group:
            for progress, frame, tag in sorted(group, reverse=True):
                if not page_tiles or (page_tiles & referenced(tag)):
                    candidate = tag
                    break
            if candidate is None:
                candidate = max(group)[2]
        else:
            # The page was so short that no sample carried its pointer.
            # Pick the frame that referenced the most of its tiles.
            best_count = 0
            for tag in all_tags:
                count = len(page_tiles & referenced(tag))
                if count > best_count:
                    best_count = count
                    candidate = tag
        if candidate is None:
            continue
        if not page_tiles:
            pages.append({"page": page_index + 1, "ok": True,
                          "no_kanji_page": True, "failures": []})
            continue
        page = check_page(index, label, outdir, candidate, page_index + 1,
                          set(visible), font)
        pages.append(page)
    present = {p["page"] for p in pages}
    missing = [i + 1 for i in range(len(records)) if i + 1 not in present]
    if not pages:
        return {"index": index, "label": label, "ok": False,
                "failures": ["no page sample"], "pages": []}
    result = {"index": index, "label": label,
              "ok": all(p["ok"] for p in pages),
              "failures": [f for p in pages for f in p["failures"]],
              "missing_pages": missing, "pages": pages}
    # Keep only failure screenshots and the report.
    shutil.rmtree(outdir, ignore_errors=True)
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--indices", default=None)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()
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
        rom = ROMS / f"pq_w{worker}.nes"
        patch_rom(index, rom, base)
        lua = LUA / f"pq_{index:04X}.lua"
        outdir = RUNS / f"{index:04X}"
        lua.write_text(lua_script(index, outdir), encoding="utf-8")
        return check_one(index, label, rom, lua, outdir, font)

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
                       "failures": [f"exception: {exc}"], "pages": []}
            results.append(res)
            if n % 25 == 0 or not res["ok"]:
                print(f"[{n}/{len(indices)}] {res['index']:04X} "
                      f"{res['label']} {'OK' if res['ok'] else 'FAIL'}")
    results.sort(key=lambda r: r["index"])
    report = {"indices": len(results),
              "empty_records": sum(1 for r in results if r.get("empty_record")),
              "failures": sum(1 for r in results if not r["ok"]),
              "pages": sum(len(r.get("pages", [])) for r in results),
              "seconds": round(time.time() - t0, 1),
              "results": results}
    (QA / "pages_report.json").write_text(json.dumps(report, indent=2),
                                          encoding="utf-8")
    print(json.dumps({k: report[k] for k in
                      ("indices", "empty_records", "failures", "pages",
                       "seconds")}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
