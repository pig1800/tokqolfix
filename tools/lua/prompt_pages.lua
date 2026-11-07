local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif (frame >= 600 and frame < 604) or (frame >= 1000 and frame < 1004)
      or (frame >= 1500 and frame < 1504) then
    emu.setInput({a=true}, 0)
  else
    emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
  end
end
local function dump(tag)
  local f = assert(io.open(outdir .. "/pp_" .. tag .. ".png", "wb"))
  f:write(emu.takeScreenshot()); f:close()
  f = assert(io.open(outdir .. "/pp_" .. tag .. "_sram.bin", "wb"))
  local t = {}
  for i = 0x6800, 0x6FFF do t[#t+1] = string.char(emu.read(i, emu.memType.nesMemory)) end
  f:write(table.concat(t)); f:close()
  local c = emu.getCpuState()
  f = assert(io.open(outdir .. "/pp_" .. tag .. ".txt", "w"))
  f:write(string.format("PC=%04X col=%02X line=%02X\n", c.pc or 0,
    emu.read(0x53, emu.memType.nesMemory), emu.read(0x56, emu.memType.nesMemory)))
  f:close()
end
local function onFrame()
  frame = frame + 1
  if frame == 900 then dump("0900") end
  if frame == 1100 then dump("1100") end
  if frame == 1400 then dump("1400") end
  if frame == 1600 then dump("1600") end
  if frame == 1800 then dump("1800"); emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
