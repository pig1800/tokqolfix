-- Screenshots of the town dialogue (frames 4415-4470) plus scroll/mask state.
local outdir = "D:/EMU/NES/tokqolfix/out/test/ramsurvey"
local tag = "k"
local frame = 0
local log = assert(io.open(outdir .. "/town_msg_" .. tag .. ".txt", "w"))
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4200 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
  elseif frame >= 4200 and frame < 4330 then
    if frame % 30 < 3 then emu.setInput({a=true}, 0) else emu.setInput({a=false}, 0) end
  elseif frame >= 4330 and frame < 5400 then
    if frame % 90 < 3 then emu.setInput({a=true}, 0) else emu.setInput({a=false}, 0) end
  else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
end
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function onFrame()
  frame = frame + 1
  if frame >= 4405 and frame <= 4480 and frame % 15 == 0 then
    local f = assert(io.open(outdir .. string.format("/town_%s_%04d.png", tag, frame), "wb")); f:write(emu.takeScreenshot()); f:close()
    log:write(string.format("f=%d scroll_x=%02X scroll_y=%02X ctrl=%02X mask=%02X band=%d\n", frame, rd(0xFC), rd(0xFD), rd(0xFF), rd(0xFE), rd(0x1E9)))
  end
  if frame == 4481 then log:close(); emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
