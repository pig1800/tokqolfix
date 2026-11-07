-- Audit internal RAM $0500-$07FF for game use outside the far loader.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local log = assert(io.open(outdir .. "/ram_audit.txt", "w"))
local seen_w = {}
local seen_r = {}
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then
    emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4200 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
    end
  elseif frame >= 4200 and frame < 6000 then
    emu.setInput({a=true}, 0)
  else
    emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
  end
end
local function wr(addr, value)
  local c = emu.getCpuState()
  local pc = c.pc or 0
  if pc >= 0x0600 and pc < 0x0700 then return end
  local key = string.format("%04X", addr)
  if not seen_w[key] then
    seen_w[key] = true
    log:write(string.format("W f=%d pc=%04X addr=%04X val=%02X\n", frame, pc, addr, value or 0))
  end
end
local function rd(addr)
  local c = emu.getCpuState()
  local pc = c.pc or 0
  if pc >= 0x0600 and pc < 0x0700 then return end
  local key = string.format("%04X", addr)
  if not seen_r[key] then
    seen_r[key] = true
    log:write(string.format("R f=%d pc=%04X addr=%04X\n", frame, pc, addr))
  end
end
local function onFrame()
  frame = frame + 1
  if frame == 6000 then log:close(); emu.stop(0) end
end
emu.addMemoryCallback(wr, emu.callbackType.write, 0x0500, 0x07FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(rd, emu.callbackType.read, 0x0500, 0x07FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
