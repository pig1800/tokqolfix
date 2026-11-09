-- Palette gate trace: standard path, then walk out of the first town's
-- building.  Logs every change of the game's palette buffer ($03E0-$03EF)
-- and screenshots every 100 frames from 5000.  tools/palette_check.py runs
-- it on the original and the kanji ROM and compares the sequences.
local frame = 0
local tag = "TAG"     -- @TAG@ (tools/palette_check.py rewrites this)
local log = assert(io.open("D:/EMU/NES/tokqolfix/out/test/r12/walk_" .. tag .. ".txt", "w"))
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function onInput()
  local f = frame
  if f >= 300 and f < 600 and (f % 60) < 3 then emu.setInput({start=true}, 0)
  elseif f >= 600 and f < 760 and (f % 60) < 3 then emu.setInput({a=true}, 0)
  elseif f >= 800 and f < 4200 then
    local phase = math.floor((f - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({}, 0) end
  elseif f >= 4200 and f < 4330 then
    if f % 30 < 3 then emu.setInput({a=true}, 0) else emu.setInput({}, 0) end
  elseif f >= 4330 and f < 4900 then
    if f % 90 < 3 then emu.setInput({a=true}, 0) else emu.setInput({}, 0) end
  elseif f >= 4900 and f < 5000 then
    if f % 20 < 3 then emu.setInput({b=true}, 0) else emu.setInput({}, 0) end
  elseif f >= 5000 and f < 5200 then emu.setInput({down=true}, 0)
  elseif f >= 5200 and f < 6600 then
    if math.floor((f - 5200) / 12) % 3 == 0 then emu.setInput({right=true}, 0) else emu.setInput({down=true}, 0) end
  else emu.setInput({}, 0) end
end
local last = ""
local function onFrame()
  frame = frame + 1
  local p = {}
  for i = 0, 15 do p[#p+1] = string.format("%02X", rd(0x03E0 + i)) end
  local s = table.concat(p, " ")
  if s ~= last then log:write(string.format("f=%d %s\n", frame, s)); last = s end
  if frame >= 5000 and frame % 100 == 0 then
    local f = assert(io.open(string.format("D:/EMU/NES/tokqolfix/out/test/r12/wz_%s_%d.png", tag, frame), "wb")); f:write(emu.takeScreenshot()); f:close()
  end
  if frame == 6700 then log:close(); emu.stop(0) end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
