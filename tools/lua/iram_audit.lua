-- Audit internal RAM candidates over the 6000-frame survey run on the original
-- ROM: every distinct address read or written in $0100-$01FF, $03C0-$03FF and
-- $0700-$07FF (any PC, including RAM-resident code), plus the minimum stack
-- pointer seen at each NMI entry.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local touched = {}
local minsp = 0xFF
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
local function mark(addr, value) touched[addr] = (touched[addr] or 0) + 1 end
local function onNmi()
  local sp = emu.getCpuState().sp or 0xFF
  if sp < minsp then minsp = sp end
end
local function onFrame()
  frame = frame + 1
  if frame == 6000 then
    local f = assert(io.open(outdir .. "/iram_audit.txt", "w"))
    f:write(string.format("min SP at NMI entry: %02X\n", minsp))
    for _, range in ipairs({{0x0100,0x01FF},{0x03C0,0x03FF},{0x0700,0x07FF}}) do
      local free = {}
      local run = nil
      for a = range[1], range[2] do
        if not touched[a] then
          if not run then run = {a, a} else run[2] = a end
        elseif run then free[#free+1] = run; run = nil end
      end
      if run then free[#free+1] = run end
      f:write(string.format("range %04X-%04X untouched runs:", range[1], range[2]))
      for _, r in ipairs(free) do f:write(string.format(" %04X-%04X(%d)", r[1], r[2], r[2]-r[1]+1)) end
      f:write("\n")
    end
    f:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(mark, emu.callbackType.write, 0x0100, 0x01FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(mark, emu.callbackType.read,  0x0100, 0x01FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(mark, emu.callbackType.write, 0x03C0, 0x03FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(mark, emu.callbackType.read,  0x03C0, 0x03FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(mark, emu.callbackType.write, 0x0700, 0x07FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(mark, emu.callbackType.read,  0x0700, 0x07FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onNmi, emu.callbackType.exec, 0xEE70, 0xEE7F, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
