local outdir = "D:/EMU/NES/tokqolfix/out/seq"
local frame = 0
local function writefile(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 900 and (frame % 60) < 3 then
    emu.setInput({a=true}, 0)
  else
    emu.setInput({start=false, a=false, b=false, select=false}, 0)
  end
end
local function onFrame()
  frame = frame + 1
  if frame >= 580 and frame <= 780 and frame % 10 == 0 then
    writefile(string.format("s_%04d.png", frame), emu.takeScreenshot())
  end
  if frame == 780 then emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
