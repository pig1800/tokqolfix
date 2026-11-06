local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local function w(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function onFrame()
  frame = frame + 1
  if frame == 120 then
    w("boot_120.png", emu.takeScreenshot())
    local t = {}
    for i = 0, 0x7FF do t[#t+1] = string.char(emu.read(i, emu.memType.nesInternalRam)) end
    w("boot_ram.bin", table.concat(t))
    local p = {}
    for i = 0, 0x2FFF do p[#p+1] = string.char(emu.read(i, emu.memType.nesPpuDebug)) end
    w("boot_ppu.bin", table.concat(p))
    emu.stop(0)
  end
end
emu.addEventCallback(onFrame, emu.eventType.endFrame)
