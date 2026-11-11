-- Map text renderer assessment (TEXT_RENDERER.md), 2026-11-12.
-- Per map-mode NMI: line.dot at flush end ($D9EA) and bytes flushed; line.dot
-- of the PPUMASK restore ($EEDA).  Env: PB_STATE, PB_PATH, PB_END, PB_OUT
local STATE = os.getenv("PB_STATE"); local OUT = os.getenv("PB_OUT"); local END = tonumber(os.getenv("PB_END"))
local keymap = {U="up",D="down",L="left",R="right",A="a",B="b",S="start",E="select"}
local sched, total = {}, 0
for s in string.gmatch(os.getenv("PB_PATH") or "", "[^,]+") do
  local k, n = s:match("^(%a)(%d+)$"); n = tonumber(n)
  for i = 1, n do sched[total+i] = keymap[k] end; total = total + n
end
local frame, lf, loaded = 0, nil, false
emu.addMemoryCallback(function()
  if loaded then return end
  loaded = true
  local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close(); emu.loadSavestate(d)
  lf = frame
end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  local k
  if lf then local f = frame - lf; k = f >= 1 and sched[f] or nil end
  if k then local t = {}; t[k] = true; emu.setInput(t, 0) else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function now() local s = emu.getState(); local sl = s["ppu.scanline"]; if sl == -1 then sl = 261 end; return sl, s["ppu.cycle"] end
local log = io.open(OUT, "w")
local r0 = 0
emu.addMemoryCallback(function() r0 = rd(0x41) end, emu.callbackType.exec, 0xD9A1, 0xD9A1, emu.memType.nesMemory, emu.cpuType.nes)
local fl, fd, nb = nil, nil, 0
emu.addMemoryCallback(function()
  local sl, d = now(); fl, fd = sl, d
  nb = (emu.getState()["cpu.x"] - r0) & 0xFF
end, emu.callbackType.exec, 0xD9EA, 0xD9EA, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function()
  if not lf then return end
  local sl, d = now()
  if fl and (rd(0x58) & 0x80) == 0 then
    log:write(string.format("%d flush_end %d.%03d bytes %d mask %d.%03d\n", frame - lf, fl, fd, nb, sl, d))
  end
  fl = nil
end, emu.callbackType.exec, 0xEEDA, 0xEEDA, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  frame = frame + 1
  if lf and frame - lf == END then log:close(); emu.stop(0) end
end, emu.eventType.endFrame)
