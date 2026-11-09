-- Palette gate (timing-independent): every run of load_text_graphics logs
-- its index, $A5 and the palette buffer before and after.  tools/
-- palette_check.py recomputes the expected buffer from the ORIGINAL ROM's
-- tables and compares.  Path: standard path + walk out of the first town.
local A_ENTRY = 0xC5A6
local A_EXIT  = 0xC5FA     -- @ltg_exit@ (the routine's rts)
local frame = 0
local log = assert(io.open("D:/EMU/NES/tokqolfix/out/test/r12/palette_loads.txt", "w"))
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function buf() local t = {} for i = 0, 31 do t[#t+1] = string.format("%02X", rd(0x03E0 + i)) end return table.concat(t, "") end
local pending = nil
emu.addMemoryCallback(function()
  pending = string.format("%d %02X %02X %s", frame, rd(0xA3), rd(0xA5), buf())
end, emu.callbackType.exec, A_ENTRY, A_ENTRY, emu.cpuType.nes, emu.memType.nesMemory)
emu.addMemoryCallback(function()
  if pending and (rd(0xED) ~= 23 or true) then
    log:write(pending .. " " .. buf() .. string.char(10)); pending = nil
  end
end, emu.callbackType.exec, A_EXIT, A_EXIT, emu.cpuType.nes, emu.memType.nesMemory)
local function onInput()
  local f = frame
  if f >= 300 and f < 600 and (f % 60) < 3 then emu.setInput({start=true}, 0)
  elseif f >= 600 and f < 760 and (f % 60) < 3 then emu.setInput({a=true}, 0)
  elseif f >= 800 and f < 4200 then
    local phase = math.floor((f - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({}, 0) end
  elseif f >= 4200 and f < 4330 then
    if f % 30 < 3 then emu.setInput({a=true}, 0) else emu.setInput({}, 0) end
  elseif f >= 4330 and f < 4900 then
    if f % 90 < 3 then emu.setInput({a=true}, 0) else emu.setInput({}, 0) end
  elseif f >= 4900 and f < 5000 then
    if f % 20 < 3 then emu.setInput({b=true}, 0) else emu.setInput({}, 0) end
  elseif f >= 5000 and f < 5200 then emu.setInput({down=true}, 0)
  elseif f >= 5200 and f < 7000 then
    if math.floor((f - 5200) / 12) % 3 == 0 then emu.setInput({right=true}, 0) else emu.setInput({down=true}, 0) end
  else emu.setInput({}, 0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(function() frame = frame + 1; if frame == 7000 then log:close(); emu.stop(0) end end, emu.eventType.endFrame)
