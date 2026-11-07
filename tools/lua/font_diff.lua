local outdir = "D:/EMU/NES/tokqolfix/out/test/fontdiff"
local frame = 0
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif (frame >= 600 and frame < 604) or (frame >= 1000 and frame < 1004)
      or (frame >= 1500 and frame < 1504) then
    emu.setInput({a=true}, 0)
  else
    emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
  end
end
local function w(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function dump(tag)
  w(tag .. ".png", emu.takeScreenshot())
  local c = {}
  for i = 0, 0x1FFF do c[#c+1] = string.char(emu.read(i, emu.memType.nesChrRam)) end
  w(tag .. "_chr.bin", table.concat(c))
  local r = {}
  for i = 0, 0x7FF do r[#r+1] = string.char(emu.read(i, emu.memType.nesMemory)) end
  w(tag .. "_ram.bin", table.concat(r))
  local p = {}
  for i = 0, 0x2FFF do p[#p+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
  w(tag .. "_ppu.bin", table.concat(p))
end
local function onFrame()
  frame = frame + 1
  if frame == 900 then dump("0900") end
  if frame == 1100 then dump("1100") end
  if frame == 1600 then dump("1600"); emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
