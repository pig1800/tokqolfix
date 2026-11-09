-- Assessment probe (map-canvas scheme, 2026-11-09).  Kanji ROM.
-- Per frame with a message window on screen (band $176 != 0 or the window's
-- corner seen): scroll, PPUCTRL shadow, screen-space tiles of rows 16-29;
-- per run: every $2007 write by PPU address range, CHR writes by tile while
-- rendering is on, nametable rows written per frame while a window opens.
-- Input: CS_STATE (.mss) + CS_PATH (one step per 40 frames, "w" = wait),
-- or the standard boot path (+ town walk) when CS_STATE is unset.
-- Output: CS_OUT (default out/test/canvas/survey.txt)
local STATE = os.getenv("CS_STATE")
local PATH = os.getenv("CS_PATH") or ""
local OUT = os.getenv("CS_OUT") or "D:/EMU/NES/tokqolfix/out/test/canvas/survey.txt"
local FRAMES = tonumber(os.getenv("CS_FRAMES") or "9000")
local SHOTDIR = os.getenv("CS_SHOTS")
local log = assert(io.open(OUT, "w"))
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuDebug) end
local frame, lf = 0, nil
local steps = {}
for s in string.gmatch(PATH, "[^,]+") do steps[#steps+1] = s end
if STATE then
  local loaded = false
  emu.addMemoryCallback(function()
    if loaded then return end
    loaded = true
    local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close()
    emu.loadSavestate(d); lf = frame
  end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
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
  elseif frame >= 4330 and frame < 9000 then
    local p = math.floor((frame - 4330) / 45) % 8
    if p == 0 then emu.setInput({a=true}, 0)
    elseif p == 2 then emu.setInput({right=true}, 0)
    elseif p == 4 then emu.setInput({a=true}, 0)
    elseif p == 6 then emu.setInput({down=true}, 0)
    else emu.setInput({}, 0) end
  else emu.setInput({}, 0) end
end
emu.addEventCallback(function()
  if not STATE then stdInput(); return end
  if not lf then emu.setInput({}, 0); return end
  local f = frame - lf - 30
  if f < 0 then emu.setInput({}, 0); return end
  local s = steps[math.floor(f / 40) + 1]
  if s and s ~= "w" and (f % 40) < 3 then local t = {}; t[s] = true; emu.setInput(t, 0)
  else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)

-- $2007 writes
local wr_range = {}
local chr_tiles = {}       -- tile address -> count (writes while frame has rendering on)
local nt_rows_frame = {}   -- "nt:row" written this frame
local nt_hi = {}
local runs = {}            -- this frame: {start, n}
local RUNLOG = os.getenv("CS_RUNS")
emu.addMemoryCallback(function()
  local st = emu.getState()
  local v = st["ppu.videoRamAddr"] & 0x3FFF
  local sl = st["ppu.scanline"]
  local k
  if v < 0x2000 then k = "chr"
    local t = v >> 4
    chr_tiles[t] = (chr_tiles[t] or 0) + 1
  elseif v < 0x3F00 then
    local q = (v - 0x2000) >> 10
    k = string.format("nt%X", 0x20 + q * 4)
    local off = v & 0x3FF
    if off < 0x3C0 then nt_rows_frame[string.format("%X:%02d", 0x20 + (q & 3) * 4, off >> 5)] = true
    else nt_rows_frame[string.format("%X:at", 0x20 + (q & 3) * 4)] = true end
  else k = "pal" end
  wr_range[k] = (wr_range[k] or 0) + 1
  if RUNLOG and v >= 0x2000 and v < 0x3F00 then
    local r = runs[#runs]
    local inc = (st["ppu.control.verticalWrite"] and 32 or 1)
    if r and r.next == v then r.n = r.n + 1; r.next = v + inc
    else runs[#runs+1] = {start = v, n = 1, next = v + inc, vert = inc == 32} end
  end
end, emu.callbackType.write, 0x2007, 0x2007, emu.memType.nesMemory, emu.cpuType.nes)

local function screen_tile(sx, sy, ctrl, x, y)
  local wx = (x + sx + (ctrl & 1) * 256) % 512
  local wy = (y + sy) % 240           -- vertical mirroring: Y wraps in one table
  local nt = wx // 256
  return ppu(0x2000 + nt * 0x400 + (wy // 8) * 32 + (wx % 256) // 8)
end
local scenes = {}
local last_key = nil
local shown_prev = false
emu.addEventCallback(function()
  frame = frame + 1
  local band = rd(0x176)
  local sx, sy, ctrl = rd(0xFD), rd(0xFC), rd(0xFF)
  -- nametable rows written this frame (window open/close pace)
  local rows = {}
  for k in pairs(nt_rows_frame) do rows[#rows+1] = k end
  nt_rows_frame = {}
  if RUNLOG and #runs > 0 then
    local parts = {}
    for _, r in ipairs(runs) do parts[#parts+1] = string.format("%04X%s%d", r.start, r.vert and "v" or "+", r.n) end
    log:write(string.format("f=%d runs sx=%02X sy=%02X ctrl=%02X band=%02X: %s", frame, sx, sy, ctrl, band, table.concat(parts, " ")) .. string.char(10))
  end
  runs = {}
  table.sort(rows)
  if #rows > 0 and #rows <= 12 then
    log:write(string.format("f=%d ntrows %s band=%02X sx=%02X sy=%02X ctrl=%02X\n", frame, table.concat(rows, " "), band, sx, sy, ctrl))
  elseif #rows > 12 then
    log:write(string.format("f=%d ntrows %d rows (bulk) band=%02X\n", frame, #rows, band))
  end
  if band ~= 0 then
    -- screen grid rows 16..29
    local grid = {}
    for r = 16, 29 do
      local line = {}
      for c = 0, 31 do line[#line+1] = string.format("%02X", screen_tile(sx, sy, ctrl, c * 8, r * 8)) end
      grid[#grid+1] = string.format("  r%02d %s", r, table.concat(line, " "))
    end
    local key = string.format("sx=%02X sy=%02X ctrl=%02X winrow=%02X wincol=%02X", sx, sy, ctrl, rd(0x177), rd(0x178))
    if not shown_prev or key ~= last_key then
      log:write(string.format("f=%d WINDOW %s\n%s\n", frame, key, table.concat(grid, "\n")))
      last_key = key
      if SHOTDIR then local f = io.open(string.format("%s/f%05d.png", SHOTDIR, frame), "wb"); f:write(emu.takeScreenshot()); f:close() end
    end
    -- flank stats, rows 18..27 (0-based), columns 0,1,22..31
    local s = scenes[key] or {flank = {}, win = {}, frames = 0}
    scenes[key] = s
    s.frames = s.frames + 1
    for r = 18, 27 do
      for c = 0, 31 do
        local t = screen_tile(sx, sy, ctrl, c * 8, r * 8)
        if c <= 1 or c >= 22 then s.flank[t] = true else s.win[t] = true end
      end
    end
  end
  shown_prev = band ~= 0
  local every = tonumber(os.getenv("CS_EVERY") or "0")
  if SHOTDIR and every > 0 and frame % every == 0 then
    local f = io.open(string.format("%s/e%05d.png", SHOTDIR, frame), "wb"); f:write(emu.takeScreenshot()); f:close()
  end
  if frame >= FRAMES then
    log:write("\n== $2007 writes by range ==\n")
    for k, v in pairs(wr_range) do log:write(string.format("  %s %d\n", k, v)) end
    log:write("== CHR tiles written (PPU tile index = addr>>4) ==\n")
    local ts = {}
    for t, n in pairs(chr_tiles) do ts[#ts+1] = t end
    table.sort(ts)
    local parts = {}
    for _, t in ipairs(ts) do parts[#parts+1] = string.format("%03X:%d", t, chr_tiles[t]) end
    log:write("  " .. table.concat(parts, " ") .. "\n")
    log:write("== scenes (window rows 18-27) ==\n")
    for key, s in pairs(scenes) do
      local fl, hi, wn, whi = {}, 0, {}, 0
      for t in pairs(s.flank) do fl[#fl+1] = t; if t >= 0x80 then hi = hi + 1 end end
      for t in pairs(s.win) do wn[#wn+1] = t; if t >= 0x80 then whi = whi + 1 end end
      table.sort(fl); table.sort(wn)
      local a, b = {}, {}
      for _, t in ipairs(fl) do a[#a+1] = string.format("%02X", t) end
      for _, t in ipairs(wn) do b[#b+1] = string.format("%02X", t) end
      log:write(string.format("%s frames=%d\n  flank uniq=%d (>=80: %d): %s\n  window cols uniq=%d (>=80: %d): %s\n", key, s.frames, #fl, hi, table.concat(a, " "), #wn, whi, table.concat(b, " ")))
    end
    log:close(); emu.stop(0)
  end
end, emu.eventType.endFrame)
