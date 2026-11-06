local outdir = "D:/EMU/NES/tokqolfix/out/status5"
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
  elseif frame >= 4800 and frame < 4830 then emu.setInput({b=true}, 0)
  elseif frame >= 5000 and frame < 5030 then emu.setInput({start=true}, 0)
  elseif frame >= 5200 and frame < 5230 then emu.setInput({down=true}, 0)
  elseif frame >= 5300 and frame < 5330 then emu.setInput({down=true}, 0)
  elseif frame >= 5400 and frame < 5430 then emu.setInput({a=true}, 0)
  elseif frame >= 5700 and frame < 5730 then emu.setInput({down=true}, 0)
  elseif frame >= 5800 and frame < 5830 then emu.setInput({down=true}, 0)
  elseif frame >= 5900 and frame < 5930 then emu.setInput({a=true}, 0)
  else
    emu.setInput({start=false,a=false,b=false,select=false,down=false}, 0)
  end
end
local function onFrame()
  frame = frame + 1
  if frame == 5600 or frame == 5700 or frame == 5800 or frame == 5900 or frame == 6000 or frame == 6100 then
    shot(string.format("s_%04d.png", frame))
  end
  if frame == 6100 then
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
