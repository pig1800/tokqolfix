local outdir = "D:/EMU/NES/tokqolfix/out/test"
local prefix = "c16e"
local frame = 0
local log = assert(io.open(outdir .. "/c16e_trace.txt", "w"))
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
  if frame <= 12 or frame % 100 == 0 then
    local s = emu.getState(); local c = emu.getCpuState()
    log:write(string.format("f=%d pc=%04X prgReg=%s chr0=%s chr1=%s off16=%s mode4k=%s\n", frame, c.pc or 0,
      tostring(s["mapper.prgReg"]), tostring(s["mapper.chrReg0"]), tostring(s["mapper.chrReg1"]), tostring(s["mapper.chrMemoryOffset16"]), tostring(s["mapper.chrMode"])))
  end
  for _, t in ipairs({900, 1100, 1240, 1720, 1960, 2300}) do
    if frame == t then w(string.format("%s_%04d.png", prefix, t), emu.takeScreenshot()) end
  end
  if frame == 2300 then log:close(); emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
