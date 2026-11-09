-- Map-canvas step 2 gate: per-frame screen digests for an A/B comparison of
-- two builds on the same input.  Three hashes per frame: lines 0-7, 8-231
-- (the NTSC picture) and 232-239, from every second pixel of every second
-- line, plus scroll_x/scroll_y/PPUCTRL shadow, plus a BG digest from the
-- nametables (screen rows 1-28 and rows 0/29), which sprites cannot disturb.
-- Env: SD_STATE (.mss, optional: else the standard boot path), SD_PATH
-- ("U16,w30,A3,..." = hold a direction/button N frames, w = wait),
-- SD_FRAMES (default 3000), SD_FOUR (1: four-screen nametables), SD_OUT,
-- SD_SHOTS (dir) + SD_SHOTF ("f1,f2,..": frames to save as PNG), SD_DUMP
-- (file) + SD_DUMPF (frames): the visible BG cells as tile.palette.
local STATE = os.getenv("SD_STATE")
local PATH = os.getenv("SD_PATH") or ""
local FRAMES = tonumber(os.getenv("SD_FRAMES") or "3000")
local OUT = os.getenv("SD_OUT")
local SHOTS = os.getenv("SD_SHOTS")
local shotf = {}
for s in string.gmatch(os.getenv("SD_SHOTF") or "", "[^,]+") do shotf[tonumber(s)] = true end
local log = assert(io.open(OUT, "w"))
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local frame, lf = 0, nil
local keymap = {U = "up", D = "down", L = "left", R = "right", A = "a", B = "b", S = "start", E = "select"}
local sched, total = {}, 0
for s in string.gmatch(PATH, "[^,]+") do
  local k, n = s:match("^(%a)(%d+)$"); n = tonumber(n)
  for i = 1, n do sched[total + i] = keymap[k] end
  total = total + n
end
if STATE then
  local loaded = false
  emu.addMemoryCallback(function()
    if loaded then return end
    loaded = true
    local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close()
    emu.loadSavestate(d); lf = frame
  end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
else
  lf = 0
end
local function stdInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4200 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({}, 0) end
  elseif frame >= 4200 and frame < 4330 then
    if frame % 30 < 3 then emu.setInput({a=true}, 0) else emu.setInput({}, 0) end
  elseif frame >= 4330 then
    local f = frame - 4330
    local k = sched[(f % math.max(total, 1)) + 1]
    if k then local t = {}; t[k] = true; emu.setInput(t, 0) else emu.setInput({}, 0) end
  else emu.setInput({}, 0) end
end
emu.addEventCallback(function()
  if not STATE then stdInput(); return end
  if not lf then emu.setInput({}, 0); return end
  local f = frame - lf - 10
  local k = f >= 1 and sched[f] or nil
  if k then local t = {}; t[k] = true; emu.setInput(t, 0) else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)
local M = 0xFFFFFFFF
local FOUR = true   -- the 4-screen formula also reads a 2-screen build right ($2800 mirrors $2000)
local function ppu(a) return emu.read(a, emu.memType.nesPpuDebug) end
-- BG digest from the nametables: tile + palette of every visible cell at
-- the frame's scroll (8-pixel cells; screen rows 1-28 = the NTSC picture).
local dumpf = {}
for s in string.gmatch(os.getenv("SD_DUMPF") or "", "[^,]+") do dumpf[tonumber(s)] = true end
local dumplog = os.getenv("SD_DUMP") and assert(io.open(os.getenv("SD_DUMP"), "w"))
local function bg_digest(f)
  local sx, sy, ctrl = rd(0xFD), rd(0xFC), rd(0xFF)
  local cx0 = (sx >> 3) + (ctrl & 1) * 32
  local cy0 = (sy >> 3) + (FOUR and ((ctrl >> 1) & 1) * 30 or 0)
  local ring = FOUR and 60 or 30
  local h, e = 0, 0
  for cy = 0, 29 do
    local ty = (cy0 + cy) % ring
    local vbase = 0x2000 + (ty >= 30 and 0x800 or 0)
    local row = ty % 30
    local hh = 0
    for cx = 0, 31 do
      local tx = (cx0 + cx) % 64
      local base = vbase + (tx >= 32 and 0x400 or 0)
      local col = tx % 32
      local t = ppu(base + row * 32 + col)
      local at = ppu(base + 0x3C0 + (row >> 2) * 8 + (col >> 2))
      local pal = (at >> (((row & 2) << 1) | (col & 2))) & 3
      hh = (hh * 31 + t * 4 + pal) & M
      if dumplog and dumpf[f] then dumplog:write(string.format("%02X.%d ", t, pal)) end
    end
    if dumplog and dumpf[f] then dumplog:write(string.format(" |r%02d\n", cy)) end
    if cy == 0 or cy == 29 then e = (e * 131 + hh) & M else h = (h * 131 + hh) & M end
  end
  return h, e
end
emu.addEventCallback(function()
  frame = frame + 1
  if not lf or frame <= lf then return end
  local f = frame - lf
  local bh, be = bg_digest(f)
  if dumplog and dumpf[f] then dumplog:write(string.format("== f=%d sx=%02X sy=%02X ctrl=%02X\n", f, rd(0xFD), rd(0xFC), rd(0xFF))) end
  local buf = emu.getScreenBuffer()
  local h0, h1, h2 = 0, 0, 0
  for y = 0, 7, 2 do
    local base = y * 256 + 1
    for x = 0, 255, 2 do h0 = (h0 * 31 + buf[base + x]) & M end
  end
  for y = 8, 231, 2 do
    local base = y * 256 + 1
    for x = 0, 255, 2 do h1 = (h1 * 31 + buf[base + x]) & M end
  end
  for y = 232, 239, 2 do
    local base = y * 256 + 1
    for x = 0, 255, 2 do h2 = (h2 * 31 + buf[base + x]) & M end
  end
  log:write(string.format("%d %08X %08X %08X %02X %02X %02X %08X %08X\n", f, h0, h1, h2, rd(0xFD), rd(0xFC), rd(0xFF), bh, be))
  if SHOTS and shotf[f] then
    local fh = io.open(string.format("%s/f%05d.png", SHOTS, f), "wb"); fh:write(emu.takeScreenshot()); fh:close()
  end
  if f >= FRAMES then log:close(); if dumplog then dumplog:close() end; emu.stop(0) end
end, emu.eventType.endFrame)
