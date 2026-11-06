local outdir = "D:/EMU/NES/tokqolfix/out/run1"
local frame = 0
local function writefile(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function shot(name)
  local png = emu.takeScreenshot()
  if png and #png > 0 then writefile(name, png) end
end
local function onInput()
  -- press start at specific frame windows, A at others
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 900 and (frame % 60) < 3 then
    emu.setInput({a=true}, 0)
  elseif frame >= 900 and frame < 1200 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  else
    emu.setInput({start=false, a=false, b=false, select=false}, 0)
  end
end
local function onFrame()
  frame = frame + 1
  if frame == 300 or frame == 450 or frame == 600 or frame == 750 or frame == 900 or frame == 1050 or frame == 1200 or frame == 1350 then
    shot(string.format("p2_%04d.png", frame))
  end
  if frame == 1350 then emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
