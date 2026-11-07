local outdir = "D:/EMU/NES/tokqolfix/out/test"
local prefix = "chr16"
local frame = 0
local function w(name, data) local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close() end
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 2400 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
  else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
end
local function onFrame()
  frame = frame + 1
  if prefix == "chr16" and frame == 3 then
    -- CHR bank 1 ($C000-$DFFF register) = page 1 for the BG table at $1000
    local v = 1
    for i = 1, 5 do emu.write(0xDFFF, v & 1, emu.memType.nesMemory); v = v >> 1 end
  end
  for _, t in ipairs({900, 1100, 1240, 1720, 1960, 2300}) do
    if frame == t then w(string.format("%s_%04d.png", prefix, t), emu.takeScreenshot()) end
  end
  if frame == 2300 then emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
