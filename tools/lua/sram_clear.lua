-- Watch SRAM writes around frame 800 to see whether the game clears it.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local log = assert(io.open(outdir .. "/sram_clear.txt", "w"))
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then
    emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 2000 then
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
local count = 0
local function onWrite(addr, value)
  if frame < 795 or frame > 805 then return end
  count = count + 1
  if count > 400 then return end
  local c = emu.getCpuState()
  log:write(string.format("f=%d pc=%04X bank=%02X addr=%04X val=%02X\n",
    frame, c.pc or 0, emu.read(0xED, emu.memType.nesMemory), addr, value or 0))
end
local function onFrame()
  frame = frame + 1
  if frame == 810 then
    log:write(string.format("total writes logged/seen: %d\n", count))
    log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onWrite, emu.callbackType.write, 0x6000, 0x7FFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
