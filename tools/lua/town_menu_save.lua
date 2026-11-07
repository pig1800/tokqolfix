-- Create the field QA save state: play from the title screen into the town,
-- open the command menu, and snapshot before selecting "talk".
-- Run with: python tools/mesen_run.py decomp/build/rom_kanji.nes tools/lua/town_menu_save.lua --name town_menu
-- It writes out/test/field_state.mss; copy it to tools/lua/town_menu.mss.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local state = nil
local err = nil
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then
    emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4200 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
    end
  elseif frame >= 4200 and frame < 4330 then
    if frame % 30 < 3 then emu.setInput({a=true}, 0)
    else emu.setInput({a=false}, 0) end
  else
    emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
  end
end
local function onTick()
  if state or err or frame < 4330 then return end
  local ok, data = pcall(function() return emu.createSavestate() end)
  if ok then state = data else err = tostring(data) end
end
local function onFrame()
  frame = frame + 1
  if frame >= 4330 and (state or err) then
    local l = assert(io.open(outdir .. "/field_state.txt", "w"))
    if state then
      local f = assert(io.open(outdir .. "/field_state.mss", "wb")); f:write(state); f:close()
      l:write("saved " .. #state .. "\n")
    else
      l:write("error " .. tostring(err) .. "\n")
    end
    l:close()
    emu.stop(0)
  end
  if frame == 5200 then emu.stop(0) end
end
emu.addMemoryCallback(onTick, emu.callbackType.exec, 0xEE79, 0xEE79, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
