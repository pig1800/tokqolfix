-- Band use (2026-11-14): where the single band page still switches.
-- Logs every KANJI_BAND write of a non-zero value (frame, PC, TXR_ON,
-- UI_BATTLE, text_graphics_index) and counts the fixed bank's band switch
-- (irq_switched) per screen class.  Env: as map_parts_timing.lua
local STATE = os.getenv("PB_STATE"); local END = tonumber(os.getenv("PB_END"))
local STD = os.getenv("PB_STD") == "1"
local keymap = {U="up",D="down",L="left",R="right",A="a",B="b",S="start",E="select"}
local sched, total = {}, 0
for s in string.gmatch(os.getenv("PB_PATH") or "", "[^,]+") do
  local k, n = s:match("^(%a)(%d+)$"); n = tonumber(n)
  for i = 1, n do sched[total+i] = keymap[k] end; total = total + n
end
local frame, lf, loaded = 0, nil, false
if STATE and STATE ~= "" then
  emu.addMemoryCallback(function()
    if loaded then return end
    loaded = true
    local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close(); emu.loadSavestate(d)
    local img = os.getenv("PB_RAMIMG")
    if img and img ~= "" then
      local g = io.open(img, "rb"); local b = g:read("*a"); g:close()
      for i = 1, #b do emu.write(0x7900 + i - 1, string.byte(b, i), emu.memType.nesMemory) end
    end
    lf = frame
  end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
else
  lf = 0
end
emu.addEventCallback(function()
  if STD then
    if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({start=true}, 0)
    elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({a=true}, 0)
    elseif frame >= 800 and frame < 4200 then
      local phase = math.floor((frame - 800) / 40) % 6
      if phase == 0 then emu.setInput({start=true}, 0) elseif phase == 2 then emu.setInput({a=true}, 0)
      elseif phase == 4 then emu.setInput({down=true}, 0) else emu.setInput({}, 0) end
    elseif frame >= 4200 and frame < 6000 then
      if frame % 30 < 3 then emu.setInput({a=true}, 0) elseif frame % 300 < 3 then emu.setInput({b=true}, 0) else emu.setInput({}, 0) end
    else emu.setInput({}, 0) end
    return
  end
  local k
  if lf then local f = frame - lf; k = f >= 1 and sched[f] or nil end
  if k then local t = {}; t[k] = true; emu.setInput(t, 0) else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)

local R = function(a) return emu.read(a, emu.memType.nesMemory) end
local KANJI_BAND, TXR_ON, UI_BATTLE, TGI = 0x0176, 0x0780, 0x7FC8, 0x00A3
local IRQ_SWITCHED = 0xC686  -- @irq_switched@
local log, sw, nset = {}, {}, 0
local function ctx() return string.format("TXR_ON %02X UI_BATTLE %02X set %d", R(TXR_ON), R(UI_BATTLE), R(TGI)) end
emu.addMemoryCallback(function(addr, value)
  if not lf or value == 0 then return end
  nset = nset + 1
  if #log < 200 then
    log[#log+1] = string.format("f%d band=%d pc %04X %s", frame - lf, value, emu.getState()["cpu.pc"], ctx())
  end
end, emu.callbackType.write, KANJI_BAND, KANJI_BAND, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function()
  if not lf then return end
  local k = ctx()
  sw[k] = (sw[k] or 0) + 1
end, emu.callbackType.exec, IRQ_SWITCHED, IRQ_SWITCHED, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  frame = frame + 1
  if lf and frame - lf == END then
    local o = io.open(os.getenv("PB_OUT"), "w")
    o:write(string.format("band set %d times\n", nset))
    for _, l in ipairs(log) do o:write(l .. "\n") end
    o:write("-- band switches (irq_switched) by context\n")
    for k, v in pairs(sw) do o:write(k .. ": " .. v .. "\n") end
    o:close(); emu.stop(0)
  end
end, emu.eventType.endFrame)
