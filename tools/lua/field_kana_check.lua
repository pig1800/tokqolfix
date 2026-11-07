-- Drive the survey inputs on the kanji ROM; from frame 4300 to 5000 dump CHR
-- and nametables every 20 frames so kana-tile integrity inside the text
-- window can be checked offline.
local outdir = "D:/EMU/NES/tokqolfix/out/test/fk"
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
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
    end
  elseif frame >= 4200 and frame < 6000 then
    if frame % 30 < 3 then emu.setInput({a=true}, 0)
    elseif frame % 300 < 3 then emu.setInput({b=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
    end
  else
    emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
  end
end
local function onFrame()
  frame = frame + 1
  if frame >= 4300 and frame <= 5000 and frame % 20 == 0 then
    local p = {}
    for i = 0, 0x27FF do p[#p+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
    w(string.format("fk_%04d_ppu.bin", frame), table.concat(p))
    local c = {}
    for i = 0, 0x1FFF do c[#c+1] = string.char(emu.read(i, emu.memType.nesChrRam)) end
    w(string.format("fk_%04d_chr.bin", frame), table.concat(c))
    local r = {}
    for i = 0, 0x7FF do r[#r+1] = string.char(emu.read(i, emu.memType.nesMemory)) end
    w(string.format("fk_%04d_ram.bin", frame), table.concat(r))
    w(string.format("fk_%04d.png", frame), emu.takeScreenshot())
  end
  if frame == 5000 then emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
