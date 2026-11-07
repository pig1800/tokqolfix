-- Log every write to zero-page $11 and $01 (copy pointers) with PC during the
-- title -> register flow, plus every write to SRAM $6800-$7FFF with PC.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local log = assert(io.open(outdir .. "/slot_ptr.txt", "w"))
local sram_pcs = {}
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
local function onZp(addr, value)
  local c = emu.getCpuState()
  if value >= 0x60 then
    log:write(string.format("f=%d pc=%04X write $%02X -> $%04X\n", frame, c.pc or 0, value, addr))
  end
end
local function onSram(addr, value)
  local c = emu.getCpuState()
  local key = string.format("%04X", c.pc or 0)
  if not sram_pcs[key] then
    sram_pcs[key] = {addr, addr, frame}
    log:write(string.format("f=%d SRAM write from pc=%s first addr=%04X\n", frame, key, addr))
  else
    if addr < sram_pcs[key][1] then sram_pcs[key][1] = addr end
    if addr > sram_pcs[key][2] then sram_pcs[key][2] = addr end
  end
end
local function onFrame()
  frame = frame + 1
  if frame == 2400 then
    for k, v in pairs(sram_pcs) do
      log:write(string.format("pc=%s wrote range %04X-%04X (first f=%d)\n", k, v[1], v[2], v[3]))
    end
    log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onZp, emu.callbackType.write, 0x0011, 0x0011, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onZp, emu.callbackType.write, 0x0001, 0x0001, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onSram, emu.callbackType.write, 0x6800, 0x7FFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
