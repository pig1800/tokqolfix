-- Revision-17 gate (PLAN rule 11): does sprite 0 hit on every band frame?
-- From a save state with a scripted input path (SHOP_STATE, SHOP_PATH: one
-- step every 40 frames from load+30, "w" = wait), per frame: the epilogue's
-- poll, hit or miss, sprite-0 corrections in vblank (spr0_fix), the scroll,
-- sprite 0 as it is in OAM, and whether the window's corner is drawn.
-- A miss with the band on and the corner drawn is a failure: the kanji
-- below the border show page 1 for that frame.
-- Output BT_OUT (default out/test/r17/band_timing.txt); BT_FRAMES frames;
-- BT_SHOTS=f1,f2,... adds screenshots and the window's nametable rows.
-- Hack addresses: python tools/lua_addrs.py tools/lua/band_timing.lua
local A_EF31  = 0x8A02  -- @nmi_ef31@
local A_POLL  = 0x8A3E  -- @band_poll@
local A_MISS  = 0x8A65  -- @band_miss@
local A_HIT   = 0x8A73  -- @band_switched@
local A_FIX   = 0xBB16  -- @spr0_fix@
local STATE = os.getenv("SHOP_STATE")
local PATH = os.getenv("SHOP_PATH") or ""
local OUT = os.getenv("BT_OUT") or "D:/EMU/NES/tokqolfix/out/test/r17/band_timing.txt"
local FRAMES = tonumber(os.getenv("BT_FRAMES") or "1500")
local NL = string.char(10)
local log = assert(io.open(OUT, "w"))
local SHOTS = {}
for s in string.gmatch(os.getenv("BT_SHOTS") or "", "[^,]+") do SHOTS[tonumber(s)] = true end
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local function oam(a) return emu.read(a, emu.memType.nesSpriteRam) end
local steps = {}
for s in string.gmatch(PATH, "[^,]+") do steps[#steps+1] = s end
local loaded, lf, frame = false, nil, 0
emu.addMemoryCallback(function()
  if loaded then return end
  loaded = true
  local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close()
  emu.loadSavestate(d)
end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  if not lf then emu.setInput({}, 0); return end
  local f = frame - lf - 30
  if f < 0 then emu.setInput({}, 0); return end
  local s = steps[math.floor(f / 40) + 1]
  if s and s ~= "w" and (f % 40) < 3 then local t = {}; t[s] = true; emu.setInput(t, 0)
  else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)
local function hackmapped()
  return rd(0x8000) == 0x4C and rd(0x8003) == 0x4C and rd(0x8006) == 0x4C
end
local ev = {}
local hit, miss = false, false
local function at(name)
  local st = emu.getState()
  ev[#ev+1] = string.format("%s@%d.%d", name, st["ppu.scanline"], st["ppu.cycle"])
end
emu.addEventCallback(function() at("nmi") end, emu.eventType.nmi)
local MARK = {[A_EF31] = "ef31", [A_POLL] = "poll", [A_MISS] = "MISS", [A_HIT] = "HIT", [A_FIX] = "FIX"}
for a, n in pairs(MARK) do
  emu.addMemoryCallback(function()
    if hackmapped() then
      at(n)
      if n == "HIT" then hit = true elseif n == "MISS" then miss = true end
    end
  end, emu.callbackType.exec, a, a, emu.memType.nesMemory, emu.cpuType.nes)
end
emu.addMemoryCallback(function(addr, v)
  local st = emu.getState()
  ev[#ev+1] = string.format("w2005=%02X@%d.%d", v, st["ppu.scanline"], st["ppu.cycle"])
end, emu.callbackType.write, 0x2005, 0x2005, emu.memType.nesMemory, emu.cpuType.nes)
local n_hit, n_miss, n_fail, n_fix = 0, 0, 0, 0
local fails = {}
emu.addEventCallback(function()
  frame = frame + 1
  if loaded and not lf then lf = frame end
  if lf and frame > lf + 1 then
    local wr, wc = rd(0x177), rd(0x178)
    local wnt = (wc & 0x20) ~= 0 and 1 or 0
    local c0 = wc & 0x1F
    local corner = ppu(0x2000 + wnt * 0x400 + wr * 32 + c0)
    local side = ppu(0x2000 + wnt * 0x400 + (wr + 1) * 32 + c0)
    local line = string.format("f=%d band=%d fl=%02X win=%d,%02X corner=%02X side=%02X sc=%d,%d ctrl=%02X spr0=%d,%02X,%02X,%d shadow=%d,%d | %s",
      frame - lf, rd(0x176), rd(0x17B), wr, wc, corner, side, rd(0xFD), rd(0xFC), rd(0xFF),
      oam(0), oam(1), oam(2), oam(3), rd(0x200), rd(0x203), table.concat(ev, " "))
    log:write(line .. NL)
    for _, e in ipairs(ev) do if e:sub(1, 4) == "FIX@" then n_fix = n_fix + 1 end end
    if hit then n_hit = n_hit + 1 end
    if miss then
      n_miss = n_miss + 1
      if corner == 0x6D then
        n_fail = n_fail + 1
        if #fails < 20 then fails[#fails+1] = line end
      end
    end
    if SHOTS[frame - lf] then
      local sf = assert(io.open(string.format("%s_f%04d.png", OUT, frame - lf), "wb")); sf:write(emu.takeScreenshot()); sf:close()
      for r = wr - 1, 29 do
        local t = {}
        for c = 0, 31 do t[#t+1] = string.format("%02X", ppu(0x2000 + wnt * 0x400 + r * 32 + c)) end
        log:write(string.format("  nt r%02d %s", r, table.concat(t, " ")) .. NL)
      end
    end
  end
  ev = {}; hit = false; miss = false
  if lf and frame - lf >= FRAMES then
    log:write(string.format("SUMMARY frames %d, hits %d, misses %d, misses with the window corner drawn %d, sprite-0 fixes %d", FRAMES, n_hit, n_miss, n_fail, n_fix) .. NL)
    for _, l in ipairs(fails) do log:write("  FAIL " .. l .. NL) end
    log:close(); emu.stop(0)
  end
end, emu.eventType.endFrame)
