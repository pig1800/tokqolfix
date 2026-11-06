local outdir = "D:/EMU/NES/tokqolfix/out/trace_kanji2"
local frame = 0
local log = {}
local logging = false
local function writefile(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function onPpuWrite(addr, value)
  if logging and addr >= 0x1100 and addr <= 0x117F then
    log[#log+1] = string.format("%04X %02X", addr, value)
  end
end
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
  elseif frame >= 5700 and frame < 5706 then emu.setInput({down=true}, 0)
  elseif frame >= 5750 and frame < 5756 then emu.setInput({down=true}, 0)
  elseif frame >= 5850 and frame < 5856 then emu.setInput({down=true}, 0)
  elseif frame >= 5950 and frame < 5956 then emu.setInput({a=true}, 0)
  elseif frame >= 6100 and frame < 6106 then emu.setInput({a=true}, 0)
  else
    emu.setInput({start=false,a=false,b=false,select=false,down=false}, 0)
  end
end
local function onFrame()
  frame = frame + 1
  if frame == 6000 then logging = true end
  if frame == 6300 then
    writefile("ppu_writes.txt", table.concat(log, "\n") .. "\n")
    writefile("screen.png", emu.takeScreenshot())
    emu.stop(0)
  end
end
emu.addEventCallback(onPpuWrite, emu.memCallbackType.ppuWrite, 0x1100, 0x117F)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
