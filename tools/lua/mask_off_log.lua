-- Log frames where the PPUMASK shadow has rendering off, over the
-- scene_survey-style long run, to see whether every scene change passes
-- through a rendering-off window.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local log = assert(io.open(outdir .. "/mask_off.txt", "w"))
local off_start = nil
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then
    emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 6000 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
    end
  else
    emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
  end
end
local function onFrame()
  frame = frame + 1
  local mask = emu.read(0xFE, emu.memType.nesInternalRam)
  local off = (mask & 0x18) == 0
  if off and not off_start then off_start = frame end
  if (not off) and off_start then
    log:write(string.format("rendering off frames %d-%d (%d frames) textmode=%02X gamemode=%02X\n",
      off_start, frame - 1, frame - off_start,
      emu.read(0x50, emu.memType.nesInternalRam), emu.read(0x87, emu.memType.nesInternalRam)))
    off_start = nil
  end
  if frame % 240 == 0 then
    local f = assert(io.open(outdir .. string.format("/maskoff_%04d.png", frame), "wb"))
    f:write(emu.takeScreenshot()); f:close()
  end
  if frame == 6000 then log:close(); emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
