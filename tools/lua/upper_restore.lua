-- Dump CHR and full SRAM around the history prompt to verify the upper-tile
-- save area and the restore at message exit.
local outdir = "D:/EMU/NES/tokqolfix/out/test/upper"
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
local function dump(tag)
  local p = {}
  for i = 0, 0x2FFF do p[#p+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
  w(tag .. "_ppu.bin", table.concat(p))
  local s = {}
  for i = 0x6000, 0x7FFF do s[#s+1] = string.char(emu.read(i, emu.memType.nesMemory)) end
  w(tag .. "_sram.bin", table.concat(s))
  w(tag .. ".png", emu.takeScreenshot())
end
local function onFrame()
  frame = frame + 1
  if frame == 950 or frame == 1100 or frame == 1240 then dump(string.format("f%04d", frame)) end
  if frame >= 1580 and frame <= 1660 and frame % 5 == 0 then
    dump(string.format("f%04d", frame))
  end
  if frame == 1700 then emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
