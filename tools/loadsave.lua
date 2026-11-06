local outdir = "D:/EMU/NES/tokqolfix/out/loadsave"
local frame = 0
local function shot(n) local f=assert(io.open(outdir.."/"..n,"wb")); f:write(emu.takeScreenshot()); f:close() end
local function onInput()
  if frame >= 300 and frame < 303 then emu.setInput({start=true},0)
  elseif frame >= 520 and frame < 545 then emu.setInput({down=true},0)
  elseif frame >= 580 and frame < 590 then emu.setInput({a=true},0)
  else emu.setInput({start=false,a=false,b=false,select=false,down=false},0) end
end
local function onFrame()
  frame=frame+1
  if frame==580 or frame==650 or frame==800 or frame==1000 then shot(string.format("s_%04d.png",frame)) end
  if frame==1000 then emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
