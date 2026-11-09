-- Visible-garble gate (revision 12).  Every frame, for every background
-- cell on screen, decide which CHR page the PPU actually used for it
-- (MMC1 CHR register 1 is tracked write by write, with the scanline of the
-- commit) and flag:
--   kanji_on_scene  an active kanji tile drawn from page 1 (shows kana junk)
--   not_uploaded    an active kanji tile drawn from page 2 whose page-2
--                   pattern still equals page 1 (glyph not uploaded yet)
--   band_mismatch   a non-kanji tile drawn from page 2 whose pattern
--                   differs from page 1
--   released_shown  a cell that showed kanji tile t keeps t after t was
--                   released (now kana junk or a different glyph)
--   kanji_left      a cell that showed kanji tile t still shows t on page 1
--                   after the window's corner is gone (window erased from
--                   the top while its text rows are still drawn)
-- Input schedule = the standard path shifted by GARBLE_OFFSET frames.
-- Output: out/test/r12/garble_<offset>.txt and shots of the first frames
-- of each garbled episode.
local OFF = 0          -- @OFFSET@ (tools/garble_run.py rewrites this line)
local LAST = 6000       -- @FRAMES@
local outdir = os.getenv("SHOP_OUT") or "D:/EMU/NES/tokqolfix/out/test/r16/run"
local DEBUG = false      -- @DEBUG@
local tag = os.getenv("SHOP_TAG") or "k"
local log = assert(io.open(string.format("%s/garble_%s_%d.txt", outdir, tag, OFF), "w"))
local frame = 0
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local function chr(a) return emu.read(a, emu.memType.nesChrRam) end

local PATH = os.getenv("SHOP_PATH") or "up,a"
local STATE = os.getenv("SHOP_STATE") or "D:/EMU/NES/tokqolfix/out/user/shop_k/rom_kanji_1.mss"
local steps = {}
for s in string.gmatch(PATH, "[^,]+") do steps[#steps+1] = s end
local loaded, lf = false, nil
local function onExecLoad()
  if loaded then return end
  loaded = true
  local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close()
  emu.loadSavestate(d)
end
emu.addMemoryCallback(onExecLoad, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
-- one step every 40 frames from load+30; "w" = wait
local function onInput()
  if not lf then emu.setInput({}, 0); return end
  local f = frame - lf - 30
  if f < 0 then emu.setInput({}, 0); return end
  local k = math.floor(f / 40) + 1
  local s = steps[k]
  if s and s ~= "w" and (f % 40) < 3 then
    local t = {}; t[s] = true; emu.setInput(t, 0)
  else emu.setInput({}, 0) end
end

-- MMC1 shift register model (CHR register 1 only matters here).
local sr, cnt = 0, 0
local reg1 = 1
local events = {}
local function onMapper(addr, value)
  if (value & 0x80) ~= 0 then sr, cnt = 0, 0; return end
  sr = sr | ((value & 1) << cnt)
  cnt = cnt + 1
  if cnt == 5 then
    if addr >= 0xC000 and addr <= 0xDFFF then
      reg1 = sr & 0x0F
      events[#events+1] = {emu.getState()["ppu.scanline"], reg1}
    end
    sr, cnt = 0, 0
  end
end

local page_prev = 1
local counts = {pool_outside=0, pool_glyph_changed=0, pool_on_band=0, pool_not_uploaded=0, kanji_left=0, kanji_on_scene=0, not_uploaded=0, band_mismatch=0, released_shown=0, active_outside=0, glyph_changed=0}
-- Battle pool kanji (revision 18): tiles $A4-$DF on the scene page while
-- the pool is armed ($0178 bit 6).  Inside the window (or a cell that
-- showed the kanji before its border was erased) the tile must be drawn
-- from page 1, uploaded, and stable; anywhere else the game itself shows
-- a pool tile, which the kanji would overwrite.
local pmarks, psigs = {}, {}
local function pool_cell(a, t, x, ytop, pg_top, pg_bot, isin, bad)
  if not isin and pmarks[a] ~= t then
    counts.pool_outside = counts.pool_outside + 1; bad[#bad+1] = string.format("pool_outside (%d,%d) t=%02X", x, ytop, t)
    return
  end
  local sg, nz = {}, false
  for i = 0, 15 do local b = emu.read(0x1000 + t * 16 + i, emu.memType.nesChrRam); sg[#sg+1] = b; if b ~= 0 then nz = true end end
  sg = table.concat(sg, ",")
  if pmarks[a] == t and psigs[a] and psigs[a] ~= sg then
    counts.pool_glyph_changed = counts.pool_glyph_changed + 1; bad[#bad+1] = string.format("pool_glyph_changed (%d,%d) t=%02X", x, ytop, t)
  end
  pmarks[a] = t; psigs[a] = sg
  if pg_top ~= 1 or pg_bot ~= 1 then
    counts.pool_on_band = counts.pool_on_band + 1; bad[#bad+1] = string.format("pool_on_band (%d,%d) t=%02X pg=%d/%d", x, ytop, t, pg_top, pg_bot)
  end
  if not nz then
    counts.pool_not_uploaded = counts.pool_not_uploaded + 1; bad[#bad+1] = string.format("pool_not_uploaded (%d,%d) t=%02X", x, ytop, t)
  end
end
local frames_bad = 0
local episodes = {}
local in_ep = false
local shots = 0
local marks = {}       -- nt address -> kanji tile shown there
local sigs = {}        -- nt address -> page-2 pattern first shown there
local function onFrame()
  frame = frame + 1
  if loaded and not lf then lf = frame end
  if lf and (frame - lf) % 20 == 0 and (frame - lf) <= 40 * #steps + 60 then
    local sf = assert(io.open(string.format("%s/p_%s_f%04d.png", outdir, tag, frame - lf), "wb")); sf:write(emu.takeScreenshot()); sf:close()
  end
  -- page timeline for this frame's visible scanlines
  local p0 = page_prev
  local changes = {}
  for _, e in ipairs(events) do
    local sl, v = e[1], e[2]
    if sl >= 240 or sl < 0 then p0 = v else changes[#changes+1] = e end
  end
  local final = p0
  for _, e in ipairs(changes) do final = e[2] end
  if DEBUG and frame >= 645 and frame <= 650 then
    local parts = {}
    for _, e in ipairs(events) do parts[#parts+1] = e[1] .. ":" .. e[2] end
    log:write(string.format("dbg f=%d p0=%d ev=%s" .. string.char(10), frame, p0, table.concat(parts, " ")))
  end
  events = {}
  local function page_at(y)
    local p = p0
    for _, e in ipairs(changes) do if e[1] < y then p = e[2] end end
    return p
  end
  page_prev = final
  if not lf or frame < lf + 2 then return end
  local mask = rd(0xFE)
  if (mask & 0x08) == 0 then marks = {}; sigs = {}; return end
  local sx, sy, ctrl = rd(0xFD), rd(0xFC), rd(0xFF)
  if rd(0xF0) ~= 0 then return end            -- split-screen modes: not band frames
  local bgbase = (ctrl & 0x10) ~= 0
  if not bgbase then return end
  local A = {}
  for i = 0, 15 do A[i] = rd(0x140 + i) end
  local diffcache = {}
  local function differs(t)
    local d = diffcache[t]
    if d == nil then
      d = false
      local p1, p2 = 0x1000 + t * 16, 0x2000 + t * 16
      for i = 0, 15 do if chr(p1 + i) ~= chr(p2 + i) then d = true; break end end
      diffcache[t] = d
    end
    return d
  end
  -- text window interior (nametable cells) from the corner the overlay
  -- computed; nothing is checked for kanji when the window is not there
  local inside = {}
  local wr, wc = rd(0x177), rd(0x178)
  local wnt = (wc & 0x20) ~= 0 and 1 or 0
  local c0 = wc & 0x1F
  local function nta(r, k)      -- row r, column k counted across both nametables
    local nt = (wnt + (k >> 5)) % 2
    return 0x2000 + nt * 0x400 + r * 32 + (k & 31)
  end
  if ppu(nta(wr, c0)) == 0x6D then
    local c1 = c0 + 1
    while c1 < c0 + 33 and ppu(nta(wr, c1)) == 0x0C do c1 = c1 + 1 end
    local r1 = wr + 1
    while r1 < 30 and ppu(nta(r1, c0)) == 0x7D do r1 = r1 + 1 end
    for r = wr + 1, r1 - 1 do
      for k = c0 + 1, c1 - 1 do inside[nta(r, k)] = true end
    end
  end
  local bad = {}
  local fine = sy % 8
  local seen = {}
  for row = 0, 30 do
    local ytop = row * 8 - fine
    if ytop <= 239 then
      local wy = (ytop + sy) % 240
      local trow = math.floor(wy / 8)
      local ymid = math.max(ytop, 0)
      local pg_top = page_at(ymid)
      local pg_bot = page_at(math.min(ytop + 7, 239))
      for x = 0, 255, 8 do
        local wx = x + sx + (ctrl & 1) * 256
        local nt = math.floor(wx / 256) % 2
        local tcol = math.floor((wx % 256) / 8)
        local a = 0x2000 + nt * 0x400 + trow * 32 + tcol
        if not seen[a] then
          seen[a] = true
          local t = ppu(a)
          local active = t < 0x80 and (A[t >> 3] & (0x80 >> (t & 7))) ~= 0
          local pool = t >= 0xA4 and t <= 0xDF and (rd(0x178) & 0x40) ~= 0
          if not pool and pmarks[a] then pmarks[a] = nil; psigs[a] = nil end
          if pool then
            pool_cell(a, t, x, ytop, pg_top, pg_bot, inside[a], bad)
          elseif active and inside[a] then
            if pg_top == 2 and pg_bot == 2 then
              local sg = {}
              for i = 0, 15 do sg[#sg+1] = chr(0x2000 + t * 16 + i) end
              sg = table.concat(sg, ",")
              if marks[a] == t and sigs[a] and sigs[a] ~= sg then
                counts.glyph_changed = counts.glyph_changed + 1; bad[#bad+1] = string.format("glyph_changed (%d,%d) t=%02X", x, ytop, t)
              end
              sigs[a] = sg
            end
            marks[a] = t
            if pg_top ~= 2 or pg_bot ~= 2 then
              counts.kanji_on_scene = counts.kanji_on_scene + 1; bad[#bad+1] = string.format("kanji_on_scene (%d,%d) t=%02X pg=%d/%d", x, ytop, t, pg_top, pg_bot)
            elseif not differs(t) then
              counts.not_uploaded = counts.not_uploaded + 1; bad[#bad+1] = string.format("not_uploaded (%d,%d) t=%02X", x, ytop, t)
            end
          else
            if marks[a] then
              if marks[a] == t and inside[a] then
                counts.released_shown = counts.released_shown + 1; bad[#bad+1] = string.format("released_shown (%d,%d) t=%02X", x, ytop, t)
              elseif marks[a] == t and active then
                -- window border gone (erase in progress), kanji still drawn
                if (pg_top ~= 2 or pg_bot ~= 2) and differs(t) then
                  counts.kanji_left = (counts.kanji_left or 0) + 1; bad[#bad+1] = string.format("kanji_left (%d,%d) t=%02X pg=%d/%d", x, ytop, t, pg_top, pg_bot)
                end
              else
                marks[a] = nil; sigs[a] = nil
              end
            end
            if (pg_top == 2 or pg_bot == 2) and differs(t) then
              if active then
                counts.active_outside = counts.active_outside + 1; bad[#bad+1] = string.format("active_outside (%d,%d) t=%02X win=%s", x, ytop, t, next(inside) and "yes" or "no")
              else
                counts.band_mismatch = counts.band_mismatch + 1; bad[#bad+1] = string.format("band_mismatch (%d,%d) t=%02X", x, ytop, t)
              end
            end
          end
        end
      end
    end
  end
  if #bad > 0 then
    frames_bad = frames_bad + 1
    if not in_ep then
      in_ep = true
      episodes[#episodes+1] = {start=frame, stop=frame, n=0, first=bad[1], band=rd(0x176), fl=rd(0x17B), req=rd(0x174), row=rd(0x177), col=rd(0x178), sy=sy, sx=sx, ctrl=ctrl}
    end
    local ep = episodes[#episodes]
    ep.stop = frame; ep.n = ep.n + 1
    if ep.n <= 2 and shots < 40 then
      shots = shots + 1
      local f = assert(io.open(string.format("%s/g_%s_%d_f%05d.png", outdir, tag, OFF, frame), "wb")); f:write(emu.takeScreenshot()); f:close()
    end
  else
    in_ep = false
  end
  if lf and frame == lf + 40 * #steps + 90 then
    log:write(string.format("offset %d, frames %d\n", OFF, LAST))
    log:write(string.format("frames with visible garble: %d\n", frames_bad))
    for k, v in pairs(counts) do log:write(string.format("  %s cells: %d\n", k, v)) end
    log:write(string.format("episodes: %d\n", #episodes))
    for _, ep in ipairs(episodes) do
      log:write(string.format("  f=%d-%d (%d frames) band=%d fl=%02X req=%d win=%d,%02X scroll=%d,%d ctrl=%02X first: %s", ep.start, ep.stop, ep.n, ep.band, ep.fl, ep.req, ep.row, ep.col, ep.sx, ep.sy, ep.ctrl, ep.first) .. string.char(10))
    end
    log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onMapper, emu.callbackType.write, 0x8000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
