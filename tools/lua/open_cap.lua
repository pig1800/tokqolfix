-- Capture every 2nd frame 1-1000 on the standard input path, plus the
-- scanline of each PPUADDR/PPUSCROLL/PPUCTRL write made after scanline 0
-- (mid-frame raster writes) with the PC.  TAGDIR is substituted per run.
local outdir = "TAGDIR"
local frame = 0
local log = assert(io.open(outdir .. "/raster.txt", "w"))
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4200 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
  else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
end
local function onReg(addr, value)
  local s = emu.getState()
  local sl = s["ppu.scanline"]
  if sl and sl >= 0 and sl < 240 then
    log:write(string.format("f=%d sl=%d cyc=%s %04X<=%02X pc=%04X\n", frame, sl, tostring(s["ppu.cycle"]), addr, value, emu.getCpuState().pc))
  end
end
local function onFrame()
  frame = frame + 1
  if frame % 2 == 0 and frame <= 1000 then
    local f = assert(io.open(string.format("%s/f%04d.png", outdir, frame), "wb")); f:write(emu.takeScreenshot()); f:close()
  end
  if frame == 1000 then log:close(); emu.stop(0) end
end
emu.addMemoryCallback(onReg, emu.callbackType.write, 0x2000, 0x2007, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onReg, emu.callbackType.write, 0xA000, 0xDFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
