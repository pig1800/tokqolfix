-- Where is the CPU during the oath freeze?  Sample PC/SP/queue state each
-- frame 2340-2420 and histogram executed RAM addresses in $0100-$01FF.
local outdir = "D:/EMU/NES/tokqolfix/out/test/rev9diag"
local frame = 0
local log = assert(io.open(outdir .. "/freeze.txt", "w"))
local ramexec = {}
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4200 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
  else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
end
local function onRamExec(addr)
  if frame >= 2340 then ramexec[addr] = (ramexec[addr] or 0) + 1 end
end
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function onFrame()
  frame = frame + 1
  if frame >= 2340 and frame <= 2420 then
    local c = emu.getCpuState()
    log:write(string.format("f=%d pc=%04X sp=%02X bank=%02X qr=%02X qw=%02X pages_left=%02X entry=%02X band=%d busy=%d tasks=%02X %02X %02X %02X\n",
      frame, c.pc, c.sp, rd(0x43), rd(0x41), rd(0x40), rd(0x138), rd(0x139), rd(0x1E9), rd(0xEC),
      rd(0x20), rd(0x24), rd(0x28), rd(0x2C)))
  end
  if frame == 2420 then
    local keys = {}
    for a in pairs(ramexec) do keys[#keys+1] = a end
    table.sort(keys)
    for _, a in ipairs(keys) do log:write(string.format("ramexec %04X x%d\n", a, ramexec[a])) end
    log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onRamExec, emu.callbackType.exec, 0x0100, 0x01FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
