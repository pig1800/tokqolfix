-- Watch writes to the kanji SRAM range ($6800-$7FFF) during the long run.
-- Writes from the RAM far loader ($0600-$06FF) and the RAM overlay
-- ($7002-$73FF) are expected; any other PC is a conflict.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local seen = {}
local total = 0
local samples = {}
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then
    emu.setInput({a=true}, 0)
  elseif frame >= 800 then
    if frame % 20 < 3 then emu.setInput({a=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
  else
    emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
  end
end
local function onWrite(addr, value)
  total = total + 1
  local c = emu.getCpuState()
  local pc = c.pc or 0
  local in_loader = pc >= 0x0600 and pc < 0x0700
  local in_overlay = pc >= 0x7002 and pc < 0x8000
  if pc >= 0 and not in_loader and not in_overlay then
    local key = string.format("%04X", pc)
    seen[key] = (seen[key] or 0) + 1
  end
  if total <= 5 then
    samples[#samples+1] = string.format("sample addr=%04X value=%02X PC=%04X", addr, value or 0, pc)
  end
end
local function onFrame()
  frame = frame + 1
  if frame == 6000 then
    local keys = {}
    for k in pairs(seen) do keys[#keys+1] = k end
    table.sort(keys)
    local f = assert(io.open(outdir .. "/sram_watch.txt", "w"))
    f:write(string.format("total_writes=%d\n", total))
    for _, s in ipairs(samples) do f:write(s .. "\n") end
    for _, k in ipairs(keys) do
      f:write(string.format("%s %d\n", k, seen[k]))
    end
    f:close()
    emu.stop(0)
  end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
emu.addMemoryCallback(onWrite, emu.callbackType.write, 0x6800, 0x7FFF,
  emu.memType.nesMemory, emu.cpuType.nes)
