-- Map text renderer assessment (TEXT_RENDERER.md), 2026-11-12.
-- Which main-thread PCs produce the queue bytes that become map-mode text
-- cells (nametable bytes < $80)?  Env: PB_STATE, PB_PATH, PB_END, PB_OUT
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
local writer = {}
emu.addMemoryCallback(function(addr, value)
  local s = emu.getState()
  writer[addr & 0xFF] = string.format("%04X", s["cpu.pc"])
end, emu.callbackType.write, 0x0400, 0x04FF, emu.memType.nesMemory, emu.cpuType.nes)
local latch, hi, va, ctrl = false, 0, 0, 0
local cnt = {}
local inflush = false
emu.addMemoryCallback(function() inflush = true end, emu.callbackType.exec, 0xD9A1, 0xD9A1, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function() inflush = false end, emu.callbackType.exec, 0xD9EA, 0xD9EA, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function(addr, value)
  if addr == 0x2000 then ctrl = value
  elseif addr == 0x2006 then
    if not latch then hi = value & 0x3F else va = (hi << 8) | value end
    latch = not latch
  elseif addr == 0x2007 then
    local a = va
    va = (va + (((ctrl & 4) ~= 0) and 32 or 1)) & 0x3FFF
    if a >= 0x2000 and a < 0x3000 and (a & 0x3FF) < 0x3C0 and value < 0x80 and (rd(0x58) & 0x80) == 0 then
      local who = "direct"
      if inflush then who = writer[(emu.getState()["cpu.x"]) & 0xFF] or "?" else who = "direct@" .. string.format("%04X", emu.getState()["cpu.pc"]) end
      cnt[who] = (cnt[who] or 0) + 1
    end
  end
end, emu.callbackType.write, 0x2000, 0x2007, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function() latch = false end, emu.callbackType.read, 0x2002, 0x2002, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  frame = frame + 1
  if lf and frame - lf == END then
    local fh = io.open(OUT, "w")
    for k, v in pairs(cnt) do fh:write(k .. " " .. v .. "\n") end
    fh:close(); emu.stop(0)
  end
end, emu.eventType.endFrame)
