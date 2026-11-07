-- Dump internal page state and CHR upper at frame 1100.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local function w(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
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
  if frame == 1100 then
    local r = {}
    for i = 0x0500, 0x07FF do r[#r+1] = string.char(emu.read(i, emu.memType.nesMemory)) end
    w("internal_1100.bin", table.concat(r))
    local p = {}
    for i = 0, 0x1FFF do p[#p+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
    w("chr_1100.bin", table.concat(p))
    emu.stop(0)
  end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
