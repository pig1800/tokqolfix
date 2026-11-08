-- Log input-related state each frame in a window, on either ROM.
-- Window chosen by env-like constants below.
local outdir = "D:/EMU/NES/tokqolfix/out/test/rev9diag"
local tag = TAG or "k"
local lo, hi = LO or 2360, HI or 2700
local frame = 0
local log = assert(io.open(outdir .. "/input_" .. tag .. ".txt", "w"))
local msgs = 0
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
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function onMsg() msgs = msgs + 1; log:write(string.format("f=%d text_show_message #%d\n", frame, msgs)) end
local function onFrame()
  frame = frame + 1
  if frame >= lo and frame <= hi and frame % 2 == 0 then
    log:write(string.format("f=%d ctl=%02X btn=%02X mask=%02X t0=%02X/%02X t1=%02X/%02X t2=%02X/%02X t3=%02X/%02X fc=%02X nfc=%02X tmode=%02X gmode=%02X line=%02X col=%02X\n",
      frame, rd(0xF5), rd(0x58), rd(0x36), rd(0x20), rd(0x21), rd(0x24), rd(0x25), rd(0x28), rd(0x29), rd(0x2C), rd(0x2D),
      rd(0x59), rd(0x5A), rd(0x50), rd(0x87), rd(0x56), rd(0x53)))
  end
  if frame == hi then log:close(); emu.stop(0) end
end
emu.addMemoryCallback(onMsg, emu.callbackType.exec, 0xD124, 0xD124, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
