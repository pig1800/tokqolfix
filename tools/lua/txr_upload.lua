-- Upload timing survey (TEXT_RENDERER.md "Upload speed", 2026-11-12).
-- Classify the log with tools/txr_frames.py.  The marks $816D (nmi_up),
-- $81E3 (its end), $8090 (cv_force), $80AC (cvn_arm) are bank 26's at
-- fff6861: take them from decomp/build/kanji/txr.lst for another build.
-- Per frame: pattern-table bytes written through $2007 and the scanline of
-- the last one, nametable text cells written (tile < $80 or kanji codes),
-- the last PPU write of the vblank, TXR_UQN at the NMI, staging publishes.
-- Env: PB_STATE, PB_PATH, PB_END, PB_OUT (dir), PB_RAMIMG, PB_POKE, PB_SHOTS
local STATE = os.getenv("PB_STATE"); local OUTD = os.getenv("PB_OUT"); local END = tonumber(os.getenv("PB_END"))
local keymap = {U="up",D="down",L="left",R="right",A="a",B="b",S="start",E="select"}
local sched, total = {}, 0
for s in string.gmatch(os.getenv("PB_PATH") or "", "[^,]+") do
  local k, n = s:match("^(%a)(%d+)$"); n = tonumber(n)
  for i = 1, n do sched[total+i] = keymap[k] end; total = total + n
end
local shots = {}
for s in string.gmatch(os.getenv("PB_SHOTS") or "", "[^,]+") do shots[tonumber(s)] = true end
local POKES = {}
for a, v in string.gmatch(os.getenv("PB_POKE") or "", "(%x+)=(%x+)") do POKES[#POKES+1] = {tonumber(a,16), tonumber(v,16)} end
local frame, lf, loaded = 0, nil, false
emu.addMemoryCallback(function()
  if loaded then return end
  loaded = true
  if STATE and STATE ~= "" then
    local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close(); emu.loadSavestate(d)
    local img = os.getenv("PB_RAMIMG")
    if img and img ~= "" then
      local g = io.open(img, "rb"); local b = g:read("*a"); g:close()
      for i = 1, #b do emu.write(0x7900 + i - 1, string.byte(b, i), emu.memType.nesMemory) end
    end
  end
  lf = frame
end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
local pressed = {}
emu.addEventCallback(function()
  local k
  if lf then local f = frame - lf; k = f >= 1 and sched[f] or nil end
  if k then local t = {}; t[k] = true; emu.setInput(t, 0); pressed[frame - lf] = k else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function now() local s = emu.getState(); local sl = s["ppu.scanline"]; if sl == -1 then sl = 261 end; return sl + s["ppu.cycle"] / 341 end
local log = io.open(OUTD .. "/log.txt", "w")
local latch, hi, va, ctrl = false, 0, 0, 0
local F = {}
local function reset()
  F = {pat = 0, patl = 0, patf = nil, nt = 0, ntt = 0, ntl = 0, last = 0, uqn = -1, pub = "", nmi = nil, flushb = 0}
end
reset()
emu.addMemoryCallback(function(addr, value)
  if not lf then return end
  local a7 = addr & 0x2007
  if a7 == 0x2000 then ctrl = value
  elseif a7 == 0x2006 then
    if not latch then hi = value & 0x3F else va = (hi << 8) | value end
    latch = not latch
  elseif a7 == 0x2007 then
    local a = va
    va = (va + (((ctrl & 4) ~= 0) and 32 or 1)) & 0x3FFF
    local t = now()
    if a < 0x2000 then
      F.pat = F.pat + 1; F.patl = t; if not F.patf then F.patf = t end
    elseif a < 0x3F00 and (a & 0x3FF) < 0x3C0 then
      F.nt = F.nt + 1
      if value < 0xC0 then F.ntt = F.ntt + 1 end
      F.ntl = t
    end
    if t >= 241 then F.last = t end
  end
  if a7 == 0x2005 or a7 == 0x2006 or a7 == 0x2007 then
    local t = now(); if t >= 241 and t > F.last then F.last = t end
  end
end, emu.callbackType.write, 0x2000, 0x3FFF, emu.memType.nesMemory, emu.cpuType.nes)
-- TXR_UQN writes: main-thread publishes (value > 0 written outside the NMI)
local innmi = false
emu.addMemoryCallback(function(addr, value)
  if not lf then return end
  if value > 0 then
    local t = now()
    if t < 241 or t > 262 then F.pub = F.pub .. string.format(" pub%d@%.0f", value, t) end
  end
end, emu.callbackType.write, 0x0781, 0x0781, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  if not lf then return end
  F.nmi = now(); F.uqn = rd(0x0781)
end, emu.eventType.nmi)
local MARKS = {{0xD9EA, "fe"}, {0xEECE, "pal"}, {0xEEE0, "on"}, {0xEF08, "ef08"}, {0x7A64, "cvn"}, {0x816D, "up"}, {0x81E3, "upd"}, {0x8090, "frc"}, {0x80AC, "arm"}}
for _, m in ipairs(MARKS) do
  emu.addMemoryCallback(function()
    if not lf then return end
    local t = now()
    if t >= 241 then F.marks = (F.marks or "") .. string.format(" %s%.1f", m[2], t) end
  end, emu.callbackType.exec, m[1], m[1], emu.memType.nesMemory, emu.cpuType.nes)
end
emu.addEventCallback(function()
  frame = frame + 1
  if not lf then return end
  local f = frame - lf
  if f == 2 then for _, pk in ipairs(POKES) do emu.write(pk[1], pk[2], emu.memType.nesMemory) end end
  log:write(string.format("%d %s uqn0=%d pat=%d (tiles %.1f) patfirst=%s patlast=%s nt=%d txt=%d ntlast=%s vbl_last=%.1f%s\n",
    f, pressed[f] or "-", F.uqn, F.pat, F.pat / 8, F.patf and string.format("%.1f", F.patf) or "-",
    F.pat > 0 and string.format("%.1f", F.patl) or "-", F.nt, F.ntt, F.nt > 0 and string.format("%.1f", F.ntl) or "-",
    F.last, F.pub .. " |" .. (F.marks or "")))
  if shots[f] then local fh = io.open(string.format("%s/s_%04d.png", OUTD, f), "wb"); fh:write(emu.takeScreenshot()); fh:close() end
  reset()
  if f == END then log:close(); emu.stop(0) end
end, emu.eventType.endFrame)
