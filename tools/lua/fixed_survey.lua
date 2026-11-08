-- Watch reads and execution across the fixed bank ($C000-$FFFF) on the
-- standard 6000-frame path plus the town dialogue path.  Output: a bitmap
-- of touched bytes and the untouched runs, for the fixed-bank audit.
local outdir = "D:/EMU/NES/tokqolfix/out/test/fixedsurvey"
local frame = 0
local hit = {}
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
    if frame % 30 < 3 then emu.setInput({a=true}, 0)
    elseif frame % 300 < 3 then emu.setInput({b=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
    end
  else
    emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
  end
end
local function onHit(addr) hit[addr] = true end
local function onFrame()
  frame = frame + 1
  if frame == 6100 then
    local f = assert(io.open(outdir .. "/touched.txt", "w"))
    local runs = {}
    local start = nil
    for a = 0xC000, 0xFFFF do
      if not hit[a] then
        if not start then start = a end
      else
        if start then
          if a - start >= 2 then runs[#runs + 1] = string.format("%04X-%04X len %d", start, a - 1, a - start) end
          start = nil
        end
      end
    end
    if start then runs[#runs + 1] = string.format("%04X-FFFF len %d", start, 0x10000 - start) end
    f:write(table.concat(runs, "\n") .. "\n")
    f:close()
    emu.stop(0)
  end
end
emu.addMemoryCallback(onHit, emu.callbackType.read, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onHit, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
