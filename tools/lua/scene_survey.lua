-- Scene CHR survey: drive the original ROM through the intro, oath scene and
-- field map, dumping screenshots and CHR every 60 frames to 6000.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local prefix = "survey"
local frame = 0
local function w(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then
    emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4200 then
    -- Advance dialogue, then poke the field menu; the long A run also drives
    -- the oath scene to its end.
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
    end
  elseif frame >= 4200 and frame < 6000 then
    -- Steady dialogue advance with an occasional menu cancel.
    if frame % 30 < 3 then emu.setInput({a=true}, 0)
    elseif frame % 300 < 3 then emu.setInput({b=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
    end
  else
    emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
  end
end
local function dump(tag)
  w(prefix .. "_" .. tag .. ".png", emu.takeScreenshot())
  local c = {}
  for i = 0, 0x1FFF do c[#c+1] = string.char(emu.read(i, emu.memType.nesChrRam)) end
  w(prefix .. "_" .. tag .. "_chr.bin", table.concat(c))
  local r = emu.getCpuState()
  local f = assert(io.open(outdir .. "/" .. prefix .. "_" .. tag .. "_cpu.txt", "w"))
  f:write(string.format("PC=%04X A=%02X X=%02X Y=%02X SP=%02X P=%02X mode=%02X\n",
    r.pc or 0, r.a or 0, r.x or 0, r.y or 0, r.sp or 0, r.p or 0,
    emu.read(0x87, emu.memType.nesInternalRam)))
  f:close()
end
local function onFrame()
  frame = frame + 1
  if frame % 60 == 0 and frame <= 6000 then
    local c = {}
    for i = 0, 0x1FFF do c[#c+1] = string.char(emu.read(i, emu.memType.nesChrRam)) end
    w(string.format("surveychr_%04d.bin", frame), table.concat(c))
  end
  if frame % 240 == 0 and frame <= 6000 then dump(string.format("%04d", frame)) end
  if frame == 6000 then emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
