local outdir = "D:/EMU/NES/tokqolfix/out/test"
local n = 0
local log = assert(io.open(outdir .. "/regwrites_probe.txt", "w"))
local function onW(addr, value)
  n = n + 1
  if n <= 200 then
    local c = emu.getCpuState()
    local s = emu.getState()
    log:write(string.format("%3d pc=%04X addr=%04X val=%02X | ctrl? prgReg=%s chr0=%s chr1=%s shift=%s wramDis=%s\n",
      n, c.pc or 0, addr, value, tostring(s["mapper.prgReg"]), tostring(s["mapper.chrReg0"]), tostring(s["mapper.chrReg1"]), tostring(s["mapper.shiftCount"]), tostring(s["mapper.wramDisable"])))
  end
end
local frame = 0
local function onFrame() frame = frame + 1; if frame == 30 then log:close(); emu.stop(0) end end
emu.addMemoryCallback(onW, emu.callbackType.write, 0x8000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
