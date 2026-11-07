-- Measure NMI handler duration in CPU cycles.  A stock NTSC vblank is 2273
-- CPU cycles.  Also record which scan jobs were active when the NMI started.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local start_cycle = nil
local start_flags = 0
local max_cycles = 0
local max_flags = 0
local sum_cycles = 0
local count = 0
local over_vblank = 0
local top = {}
local function on_nmi()
  local c = emu.getCpuState()
  start_cycle = c.cycleCount
  local chr = emu.read(0x68C1, emu.memType.nesMemory)
  local vram = emu.read(0x68E7, emu.memType.nesMemory)
  local upper = emu.read(0x68EC, emu.memType.nesMemory)
  local restore = emu.read(0x68CB, emu.memType.nesMemory)
  start_flags = chr + vram * 2 + upper * 4 + restore * 8
end
local function on_exit()
  local c = emu.getCpuState()
  if start_cycle then
    local d = c.cycleCount - start_cycle
    if d < 0 then d = d + 29781 end
    if d > max_cycles then max_cycles = d; max_flags = start_flags end
    sum_cycles = sum_cycles + d
    count = count + 1
    if d > 2273 then over_vblank = over_vblank + 1 end
    top[#top + 1] = { d = d, f = start_flags }
    if #top > 20 then table.sort(top, function(a, b) return a.d > b.d end); top[21] = nil end
  end
  start_cycle = nil
end
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
local function onFrame()
  frame = frame + 1
  if frame == 2100 then
    table.sort(top, function(a, b) return a.d > b.d end)
    local f = assert(io.open(outdir .. "/nmi_budget.txt", "w"))
    f:write(string.format("max_cycles=%d flags=%d avg_cycles=%.0f samples=%d over_vblank=%d\n",
      max_cycles, max_flags, count > 0 and sum_cycles / count or 0, count, over_vblank))
    for i = 1, math.min(10, #top) do
      f:write(string.format("top %d: cycles=%d flags=%d\n", i, top[i].d, top[i].f))
    end
    f:close()
    emu.stop(0)
  end
end
emu.addMemoryCallback(on_nmi, emu.callbackType.exec, 0xEE7F, 0xEE7F,
  emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(on_exit, emu.callbackType.exec, 0xEF31, 0xEF38,
  emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
