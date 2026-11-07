local outdir = "D:/EMU/NES/tokqolfix/out/test"
local prefix = "c16b"
local frame = 0
local function w(name, data) local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close() end
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 2400 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
  else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
end
local function onFrame()
  frame = frame + 1
  for _, t in ipairs({900, 1100, 1240, 1720, 1960, 2300}) do
    if frame == t then w(string.format("%s_%04d.png", prefix, t), emu.takeScreenshot()) end
  end
  if frame == 2300 then emu.stop(0) end
end
local done = false
local function afterInit()
  if done then return end
  done = true
  local v = 1
  for i = 1, 5 do emu.write(0xDFFF, v & 1, emu.memType.nesMemory); v = v >> 1 end
end
emu.addMemoryCallback(afterInit, emu.callbackType.exec, 0xF00C, 0xF00C, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
