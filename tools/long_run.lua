local outdir = "D:/EMU/NES/tokqolfix/out/long"
local frame = 0
local function writefile(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then
    emu.setInput({a=true}, 0)
  elseif frame >= 800 then
    if frame % 20 < 3 then emu.setInput({a=true}, 0)
    else emu.setInput({start=false,a=false,b=false,select=false,down=false}, 0) end
  else
    emu.setInput({start=false,a=false,b=false,select=false,down=false}, 0)
  end
end
local function onFrame()
  frame = frame + 1
  if frame >= 1000 and frame <= 6000 and frame % 250 == 0 then
    writefile(string.format("l_%04d.png", frame), emu.takeScreenshot())
  end
  if frame == 6000 then emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
