-- Original ROM survey: which $0000-$07FF addresses are executed, and which
-- $0400-$06FF addresses are read or written, over the standard 4000-frame
-- input path.  Output: out/test/ramsurvey/survey.txt
local outdir = "D:/EMU/NES/tokqolfix/out/test/ramsurvey"
local frame = 0
local execd, touched = {}, {}
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
local function runs(t, lo, hi, want)
  local out, start = {}, nil
  for a = lo, hi + 1 do
    local v = (a <= hi) and ((t[a] ~= nil) == want) or false
    if v and not start then start = a end
    if not v and start then out[#out+1] = string.format("%04X-%04X", start, a - 1); start = nil end
  end
  return table.concat(out, " ")
end
local function onExec(addr) execd[addr] = true end
local function onTouch(addr) touched[addr] = true end
local function onFrame()
  frame = frame + 1
  if frame == 4000 then
    local f = assert(io.open(outdir .. "/survey.txt", "w"))
    f:write("executed RAM ranges 0000-07FF: " .. runs(execd, 0, 0x7FF, true) .. "\n")
    f:write("untouched 0400-06FF: " .. runs(touched, 0x400, 0x6FF, false) .. "\n")
    f:write("untouched 0100-01FF: " .. runs(touched, 0x100, 0x1FF, false) .. "\n")
    f:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onExec, emu.callbackType.exec, 0x0000, 0x07FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onTouch, emu.callbackType.read, 0x0100, 0x06FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onTouch, emu.callbackType.write, 0x0100, 0x06FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
