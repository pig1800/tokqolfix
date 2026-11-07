local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local log = assert(io.open(outdir .. "/slot_ptr2.txt", "w"))
local hits = 0
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then
    emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 2400 then
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
local function zp(a) return emu.read(a, emu.memType.nesInternalRam) end
local function onCopy()
  hits = hits + 1
  if hits <= 3 or hits % 512 == 0 then
    log:write(string.format("f=%d pc=9F7A hit=%d $00/$01=%02X%02X $10/$11=%02X%02X Y=%02X\n",
      frame, hits, zp(1), zp(0), zp(0x11), zp(0x10), emu.getCpuState().y or 0))
  end
end
local function onInit()
  log:write(string.format("f=%d init_name_entry called from pc stack; $10/$11 before=%02X%02X\n", frame, zp(0x11), zp(0x10)))
end
local function onZp11(addr, value)
  if frame >= 790 and frame <= 810 then
    log:write(string.format("f=%d pc=%04X write $%02X -> $11\n", frame, emu.getCpuState().pc or 0, value))
  end
end
local function onFrame()
  frame = frame + 1
  if frame == 1000 then log:close(); emu.stop(0) end
end
emu.addMemoryCallback(onCopy, emu.callbackType.exec, 0x9F7A, 0x9F7A, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onInit, emu.callbackType.exec, 0x9C7A, 0x9C7A, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onZp11, emu.callbackType.write, 0x0011, 0x0011, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
