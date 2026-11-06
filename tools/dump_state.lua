-- Dump NES state at a chosen frame in Mesen test runner mode.
local outdir = "D:/EMU/NES/tokqolfix/out/run1"
local frame = 0

local function writefile(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb"))
  f:write(data)
  f:close()
end

local function dump()
  local t = {}
  for i = 0, 0x1FFF do
    t[#t+1] = string.char(emu.read(i, emu.memType.nesChrRam))
  end
  writefile("chr.bin", table.concat(t))

  t = {}
  for i = 0x2000, 0x2FFF do
    t[#t+1] = string.char(emu.read(i, emu.memType.nesPpuDebug))
  end
  writefile("nametables.bin", table.concat(t))

  t = {}
  for i = 0, 0x1F do
    t[#t+1] = string.char(emu.read(i, emu.memType.nesPaletteRam))
  end
  writefile("palette.bin", table.concat(t))

  t = {}
  for i = 0, 0x7FF do
    t[#t+1] = string.char(emu.read(i, emu.memType.nesInternalRam))
  end
  writefile("ram.bin", table.concat(t))

  local png = emu.takeScreenshot()
  if png and #png > 0 then writefile("screen.png", png) end
  emu.log("dumped at frame " .. frame)
end

local function onFrame()
  frame = frame + 1
  if frame == 60 then emu.setInput(0, {start=true}, 2) end
  if frame == 120 then emu.setInput(0, {start=true}, 2) end
  if frame == 180 then emu.setInput(0, {start=true}, 2) end
  if frame == 240 then emu.setInput(0, {start=true}, 2) end
  if frame == 600 then dump(); emu.stop(0) end
end

emu.addEventCallback(onFrame, emu.eventType.endFrame)
emu.log("script loaded")
