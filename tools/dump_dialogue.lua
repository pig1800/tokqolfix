local outdir = "D:/EMU/NES/tokqolfix/out/dialogue"
local frame = 0
local function writefile(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function dump()
  local t = {}
  for i = 0, 0x1FFF do t[#t+1] = string.char(emu.read(i, emu.memType.nesChrRam)) end
  writefile("chr.bin", table.concat(t))
  t = {}
  for i = 0, 0x2FFF do t[#t+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
  writefile("ppu_0000_2fff.bin", table.concat(t))
  t = {}
  for i = 0, 0x7FF do t[#t+1] = string.char(emu.read(i, emu.memType.nesInternalRam)) end
  writefile("ram.bin", table.concat(t))
  writefile("screen.png", emu.takeScreenshot())
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
local function onFrame()
  frame = frame + 1
  if frame == 1160 then dump(); emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
