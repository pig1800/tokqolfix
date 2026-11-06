local outdir = "D:/EMU/NES/tokqolfix/out/status"
local frame = 0
local function writefile(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function shot(n) writefile(n, emu.takeScreenshot()) end
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then
    emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4000 then
    if frame % 20 < 3 then emu.setInput({a=true}, 0)
    else emu.setInput({start=false,a=false,b=false,select=false,down=false}, 0) end
  elseif frame == 4600 then emu.setInput({start=true}, 0)
  elseif frame == 4650 then emu.setInput({down=true}, 0)
  elseif frame == 4700 then emu.setInput({down=true}, 0)
  elseif frame == 4750 then emu.setInput({a=true}, 0)
  else
    emu.setInput({start=false,a=false,b=false,select=false,down=false}, 0)
  end
end
local function onFrame()
  frame = frame + 1
  if frame == 4650 or frame == 4700 or frame == 4750 or frame == 4800 or frame == 4900 or frame == 5000 then
    shot(string.format("st_%04d.png", frame))
  end
  if frame == 5000 then
    local t = {}
    for i = 0, 0x1FFF do t[#t+1] = string.char(emu.read(i, emu.memType.nesChrRam)) end
    writefile("chr.bin", table.concat(t))
    t = {}
    for i = 0, 0x2FFF do t[#t+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
    writefile("ppu_0000_2fff.bin", table.concat(t))
    t = {}
    for i = 0, 0x7FF do t[#t+1] = string.char(emu.read(i, emu.memType.nesInternalRam)) end
    writefile("ram.bin", table.concat(t))
    emu.stop(0)
  end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
