-- Load the mid-dialogue save state and advance through several pages.
-- Dumps screenshots, PPU memory, zero page, PRG RAM and CHR at each stop.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local statepath = "D:/EMU/NES/SaveStates/Tenchi o Kurau (Japan) (Rev 1)_11.mss"
local frame, loaded, press = 0, false, 0
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
  w("dlg_" .. tag .. ".png", emu.takeScreenshot())
  local p = {}
  for i = 0, 0x2FFF do p[#p+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
  w("dlg_" .. tag .. "_ppu.bin", table.concat(p))
  local r = {}
  for i = 0, 0xFF do r[#r+1] = string.char(emu.read(i, emu.memType.nesInternalRam)) end
  w("dlg_" .. tag .. "_zp.bin", table.concat(r))
  local s = {}
  for i = 0x6000, 0x7FFF do s[#s+1] = string.char(emu.read(i, emu.memType.nesMemory)) end
  w("dlg_" .. tag .. "_sram.bin", table.concat(s))
  local c = {}
  for i = 0, 0x1FFF do c[#c+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
  w("dlg_" .. tag .. "_chr.bin", table.concat(c))
end
local function onInput()
  press = press + 1
  if press % 40 < 2 then
    emu.setInput({a = true}, 0)
  else
    emu.setInput({a = false}, 0)
  end
end
local function onFrame()
  frame = frame + 1
  if frame == 40 then dump("040") end
  if frame == 120 then dump("120") end
  if frame == 220 then dump("220") end
  if frame == 340 then dump("340") end
  if frame == 500 then dump("500") end
  if frame == 700 then dump("700") end
  if frame == 900 then dump("900") end
  if frame == 1120 then dump("1120"); emu.stop(0) end
end
emu.addMemoryCallback(onExec, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
