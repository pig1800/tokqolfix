-- Assert that only the overlay and its RAM stub touch the internal-RAM
-- ranges reserved for the hack, over the 6000-frame survey input.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local bad = 0
local total = 0
local pcs = {}
local log = assert(io.open(outdir .. "/iram_watch.txt", "w"))
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
    local phase = math.floor((frame - 4200) / 30) % 4
    if phase == 0 then emu.setInput({a=true}, 0)
    elseif phase == 2 then emu.setInput({right=true}, 0)
    else emu.setInput({a=false, right=false}, 0) end
  else
    emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
  end
end
local function onWrite(addr, value)
  total = total + 1
  local pc = emu.getCpuState().pc or 0
  local bankb = emu.read(0x44, emu.memType.nesMemory)
  pcs[pc] = (pcs[pc] or 0) + 1
  local ours = (pc >= 0x0140 and pc <= 0x015F) or (pc >= 0xC63A and pc <= 0xC675)
      or ((pc >= 0xB800 and pc <= 0xBFFF) and bankb >= 18 and bankb <= 22)
  if not ours then
    bad = bad + 1
    if bad <= 40 then
      log:write(string.format("FOREIGN f=%d pc=%04X bankb=%02X addr=%04X val=%02X\n",
        frame, pc, bankb, addr, value or 0))
    end
  end
end
local function onFrame()
  frame = frame + 1
  if frame == 6000 then
    local list = {}
    for pc, n in pairs(pcs) do list[#list+1] = {pc, n} end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    log:write(string.format("total reserved-range writes: %d; foreign writes: %d\n", total, bad))
    for i = 1, math.min(#list, 20) do
      log:write(string.format("  pc=%04X count=%d\n", list[i][1], list[i][2]))
    end
    log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onWrite, emu.callbackType.write, 0x0131, 0x017F, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onWrite, emu.callbackType.write, 0x01E0, 0x01E7, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
