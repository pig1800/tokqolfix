-- Original ROM: at each text line start ($D178, after cursor_to_ppu+$21)
-- log the line's nametable address, scroll, PPUCTRL shadow and the screen
-- row it maps to.  Standard path plus the town dialogue path.
local outdir = "D:/EMU/NES/tokqolfix/out/test/ramsurvey"
local frame = 0
local seen = {}
local log = assert(io.open(outdir .. "/window_pos.txt", "w"))
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4200 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
  elseif frame >= 4200 and frame < 4330 then
    if frame % 30 < 3 then emu.setInput({a=true}, 0) else emu.setInput({a=false}, 0) end
  elseif frame >= 4330 and frame < 9000 then
    local p = math.floor((frame - 4330) / 45) % 8
    if p == 0 then emu.setInput({a=true}, 0)
    elseif p == 2 then emu.setInput({right=true}, 0)
    elseif p == 4 then emu.setInput({a=true}, 0)
    elseif p == 6 then emu.setInput({down=true}, 0)
    else emu.setInput({a=false, right=false, down=false}, 0) end
  else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
end
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function onLine()
  local hi, lo = rd(0x69), rd(0x68)
  local addr = hi * 256 + lo
  local row = math.floor((addr % 0x400) / 32)
  local col = addr % 32
  local sy, sx, ctrl = rd(0xFC), rd(0xFD), rd(0xFF)
  local scr = (row * 8 - sy) % 240
  local key = string.format("addr=%04X row=%d col=%d sy=%02X sx=%02X ctrl=%02X line=%d tmode=%02X -> screen_y=%d", addr, row, col, sy, sx, ctrl, rd(0x56), rd(0x50), scr)
  if not seen[key] then seen[key] = frame; log:write(string.format("f=%d %s\n", frame, key)) end
end
local function onFrame()
  frame = frame + 1
  if frame % 500 == 0 and frame >= 4500 then
    local f = assert(io.open(outdir .. string.format("/wp_%04d.png", frame), "wb")); f:write(emu.takeScreenshot()); f:close()
  end
  if frame == 9000 then log:close(); emu.stop(0) end
end
emu.addMemoryCallback(onLine, emu.callbackType.exec, 0xD178, 0xD178, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
