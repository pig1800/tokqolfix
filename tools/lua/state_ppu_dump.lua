-- Load the mid-dialogue save state, let the message draw, dump PPU/NT/CHR,
-- PPUCTRL shadow, and screenshots at a few frames.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local statepath = "D:/EMU/NES/SaveStates/Tenchi o Kurau (Japan) (Rev 1)_11.mss"
local frame, loaded = 0, false
local function w(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function onExec()
  if loaded then return end
  loaded = true
  local f = io.open(statepath, "rb"); local d = f:read("*a"); f:close()
  emu.loadSavestate(d)
end
local function dump(tag)
  w("state_" .. tag .. ".png", emu.takeScreenshot())
  local p = {}
  for i = 0, 0x2FFF do p[#p+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
  w("state_" .. tag .. "_ppu.bin", table.concat(p))
  local r = {}
  for i = 0, 0xFF do r[#r+1] = string.char(emu.read(i, emu.memType.nesInternalRam)) end
  w("state_" .. tag .. "_zp.bin", table.concat(r))
end
local function onFrame()
  frame = frame + 1
  if frame == 30 then dump("030") end
  if frame == 200 then dump("200"); emu.stop(0) end
end
emu.addMemoryCallback(onExec, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
