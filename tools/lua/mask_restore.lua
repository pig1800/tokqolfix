-- Log the PPU scanline when the NMI handler restores PPUMASK (end of PPU work).
-- Visible scanlines (0-239) with rendering enabled in the mask mean the top of
-- the frame was rendered blank.
local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local log = assert(io.open(outdir .. "/mask_restore.txt", "w"))
local worst = {}
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
local function onMask()
  local ok, s = pcall(emu.getState)
  local sl = -999
  if ok and type(s) == "table" then sl = s["ppu.scanline"] or -999 end
  local mask = emu.read(0xFE, emu.memType.nesInternalRam)
  if sl >= 0 and sl < 240 and (mask & 0x18) ~= 0 then
    worst[#worst+1] = string.format("f=%d scanline=%d mask=%02X", frame, sl, mask)
  end
  if frame % 10 == 0 then log:write(string.format("f=%d scanline=%d mask=%02X\n", frame, sl, mask)) end
end
local function onFrame()
  frame = frame + 1
  if frame == 2100 then
    log:write(string.format("frames with visible-scanline mask restore: %d\n", #worst))
    for i = 1, math.min(#worst, 60) do log:write(worst[i] .. "\n") end
    log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onMask, emu.callbackType.exec, 0xEEDA, 0xEEDA, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
