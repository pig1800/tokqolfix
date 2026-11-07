-- Replay the menu_explore input sequence to reach a town message window,
-- then dump PPU memory, zero page and screenshots.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local function w(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then
    emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 2000 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
    end
  else
    emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
  end
end
local function dump(tag)
  w("town_" .. tag .. ".png", emu.takeScreenshot())
  local p = {}
  for i = 0, 0x2FFF do p[#p+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
  w("town_" .. tag .. "_ppu.bin", table.concat(p))
  local r = {}
  for i = 0, 0xFF do r[#r+1] = string.char(emu.read(i, emu.memType.nesInternalRam)) end
  w("town_" .. tag .. "_zp.bin", table.concat(r))
end
local function onFrame()
  frame = frame + 1
  if frame == 1240 then dump("1240") end
  if frame == 1720 then dump("1720") end
  if frame == 1960 then dump("1960"); emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
