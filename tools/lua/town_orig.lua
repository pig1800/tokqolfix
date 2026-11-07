-- Replay the title -> new game -> town input sequence against the kanji ROM.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local prefix = "otown"
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
  local c = emu.getCpuState()
  local f = assert(io.open(outdir .. "/" .. prefix .. "_" .. tag .. "_cpu.txt", "w"))
  f:write(string.format("PC=%04X A=%02X X=%02X Y=%02X SP=%02X P=%02X\n",
    c.pc or 0, c.a or 0, c.x or 0, c.y or 0, c.sp or 0, c.p or 0))
  f:close()
  w(prefix .. "_" .. tag .. ".png", emu.takeScreenshot())
  local p = {}
  for i = 0, 0x2FFF do p[#p+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
  w(prefix .. "_" .. tag .. "_ppu.bin", table.concat(p))
  local r = {}
  for i = 0, 0x7FF do r[#r+1] = string.char(emu.read(i, emu.memType.nesInternalRam)) end
  w(prefix .. "_" .. tag .. "_ram.bin", table.concat(r))
  w(prefix .. "_" .. tag .. "_zp.bin", string.sub(table.concat(r), 1, 256))
  local s = {}
  for i = 0, 0x1FFF do s[#s+1] = string.char(emu.read(i, emu.memType.nesSaveRam)) end
  w(prefix .. "_" .. tag .. "_sram.bin", table.concat(s))
  local c = {}
  for i = 0, 0x1FFF do c[#c+1] = string.char(emu.read(i, emu.memType.nesChrRam)) end
  w(prefix .. "_" .. tag .. "_chr.bin", table.concat(c))
end
local function onFrame()
  frame = frame + 1
  if frame == 900 then dump("0900") end
  if frame == 1100 then dump("1100") end
  if frame == 1240 then dump("1240") end
  if frame == 1720 then dump("1720") end
  if frame == 1960 then dump("1960"); emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
