-- Original ROM: are the candidate fixed-bank padding ranges ever read or
-- executed?  Output: out/test/ramsurvey/fixed_reads.txt
local outdir = "D:/EMU/NES/tokqolfix/out/test/ramsurvey"
local frame = 0
local hits = {}
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4200 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
  else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
end
local function onHit(addr) hits[addr] = (hits[addr] or 0) + 1 end
local function onFrame()
  frame = frame + 1
  if frame == 4000 then
    local f = assert(io.open(outdir .. "/fixed_reads.txt", "w"))
    for _, r in ipairs({{0xFFE0, 0xFFEF}, {0xE6B3, 0xE6C3}, {0xC6C3, 0xC6D1}, {0xD3F2, 0xD403}, {0xC4BA, 0xC4CA}}) do
      local n = 0
      for a = r[1], r[2] do if hits[a] then n = n + 1 end end
      f:write(string.format("%04X-%04X: %d of %d bytes read/executed\n", r[1], r[2], n, r[2] - r[1] + 1))
    end
    f:close(); emu.stop(0)
  end
end
for _, r in ipairs({{0xFFE0, 0xFFEF}, {0xE6B3, 0xE6C3}, {0xC6C3, 0xC6D1}, {0xD3F2, 0xD403}, {0xC4BA, 0xC4CA}}) do
  emu.addMemoryCallback(onHit, emu.callbackType.read, r[1], r[2], emu.memType.nesMemory, emu.cpuType.nes)
  emu.addMemoryCallback(onHit, emu.callbackType.exec, r[1], r[2], emu.memType.nesMemory, emu.cpuType.nes)
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
