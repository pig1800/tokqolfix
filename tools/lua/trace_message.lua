-- Reach the first town message, then stop pressing buttons so the page can
-- render completely.  Dump screenshots and buffers afterwards.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 604 then
    emu.setInput({a=true}, 0)
  else
    emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
  end
end
local function dump(tag)
  local f = assert(io.open(outdir .. "/msg_" .. tag .. ".png", "wb"))
  f:write(emu.takeScreenshot()); f:close()
  local p = {}
  for i = 0, 0x2FFF do p[#p+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
  f = assert(io.open(outdir .. "/msg_" .. tag .. "_ppu.bin", "wb"))
  f:write(table.concat(p)); f:close()
  local r = {}
  for i = 0, 0x7FF do r[#r+1] = string.char(emu.read(i, emu.memType.nesInternalRam)) end
  f = assert(io.open(outdir .. "/msg_" .. tag .. "_ram.bin", "wb"))
  f:write(table.concat(r)); f:close()
  local c2 = {}
  for i = 0, 0x1FFF do c2[#c2+1] = string.char(emu.read(i, emu.memType.nesChrRam)) end
  f = assert(io.open(outdir .. "/msg_" .. tag .. "_chr.bin", "wb"))
  f:write(table.concat(c2)); f:close()
  local s = {}
  for i = 0, 0x1FFF do s[#s+1] = string.char(emu.read(i, emu.memType.nesSaveRam)) end
  f = assert(io.open(outdir .. "/msg_" .. tag .. "_sram.bin", "wb"))
  f:write(table.concat(s)); f:close()
  local c = emu.getCpuState()
  local g = assert(io.open(outdir .. "/msg_" .. tag .. ".txt", "w"))
  g:write(string.format("PC=%04X col=%02X line=%02X ptr=%02X%02X win=%02X\n",
    c.pc or 0,
    emu.read(0x53, emu.memType.nesInternalRam),
    emu.read(0x56, emu.memType.nesInternalRam),
    emu.read(0x52, emu.memType.nesInternalRam),
    emu.read(0x51, emu.memType.nesInternalRam),
    emu.read(0x46, emu.memType.nesInternalRam)))
  g:close()
end
local function onFrame()
  frame = frame + 1
  if frame == 640 then dump("640") end
  if frame == 900 then dump("900") end
  if frame == 1300 then dump("1300"); emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
