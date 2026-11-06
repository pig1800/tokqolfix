local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local function w(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function onFrame()
  frame = frame + 1
  if frame == 300 or frame == 600 then
    w("long_" .. frame .. "_" .. tostring(emu.getRomInfo().name):gsub("[^%w]","_") .. ".png", emu.takeScreenshot())
  end
  if frame == 600 then
    local t = {}
    for i = 0, 0x1FFF do t[#t+1] = string.char(emu.read(i, emu.memType.nesChrRam)) end
    w("long_chr_" .. tostring(emu.getRomInfo().name):gsub("[^%w]","_") .. ".bin", table.concat(t))
    t = {}
    for i = 0, 0x2FFF do t[#t+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
    w("long_ppu_" .. tostring(emu.getRomInfo().name):gsub("[^%w]","_") .. ".bin", table.concat(t))
    emu.stop(0)
  end
end
emu.addEventCallback(onFrame, emu.eventType.endFrame)
