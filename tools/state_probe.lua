local outdir = "D:/EMU/NES/tokqolfix/out/stateprobe"
local statepath = "D:/EMU/NES/SaveStates/Tenchi o Kurau (Japan) (Rev 1)_11.mss"
local frame = 0
local loaded = false
local function writefile(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function onExec(addr, value)
  if not loaded then
    loaded = true
    local f = io.open(statepath, "rb")
    if f then local data=f:read("*a"); f:close(); emu.loadSavestate(data) end
  end
end
local function onFrame()
  frame = frame + 1
  if frame == 5 then
    local t={}
    for i=0,0x1FFF do t[#t+1]=string.char(emu.read(i, emu.memType.nesChrRam)) end
    writefile("chr.bin", table.concat(t))
    t={}
    for i=0,0x2FFF do t[#t+1]=string.char(emu.read(i, emu.memType.nesPpuDebug)) end
    writefile("ppu.bin", table.concat(t))
    t={}
    for i=0,0x7FF do t[#t+1]=string.char(emu.read(i, emu.memType.nesInternalRam)) end
    writefile("ram.bin", table.concat(t))
    writefile("screen.png", emu.takeScreenshot())
    emu.stop(0)
  end
end
emu.addMemoryCallback(onExec, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
