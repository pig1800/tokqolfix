-- Record the minimum stack pointer at NMI entry and at overlay entries over
-- the 6000-frame survey input.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local min_nmi = 0xFF
local min_overlay = 0xFF
local log = assert(io.open(outdir .. "/stack_check.txt", "w"))
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4200 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
  elseif frame >= 4200 and frame < 6000 then
    local phase = math.floor((frame - 4200) / 30) % 4
    if phase == 0 then emu.setInput({a=true}, 0)
    elseif phase == 2 then emu.setInput({right=true}, 0)
    else emu.setInput({a=false, right=false}, 0) end
  else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
end
local function onNmi()
  local sp = emu.getCpuState().sp or 0xFF
  if sp < min_nmi then min_nmi = sp end
end
local function onOverlay()
  local sp = emu.getCpuState().sp or 0xFF
  if sp < min_overlay then min_overlay = sp end
end
local function onFrame()
  frame = frame + 1
  if frame == 6000 then
    log:write(string.format("min SP nmi=%02X overlay=%02X; reserved state starts at $0131 (SP=$31)\n",
      min_nmi, min_overlay))
    log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onNmi, emu.callbackType.exec, 0xEE70, 0xEE7F, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onOverlay, emu.callbackType.exec, 0xB800, 0xB800, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
