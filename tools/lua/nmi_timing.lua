-- Original ROM: scanline/cycle at NMI entry ($EE79), at loc_EF08 (normal
-- frames, before sound) and at loc_EF31 (epilogue); queue state at entry
-- in split frames.  Standard path + town, 9000 frames.
local outdir = "D:/EMU/NES/tokqolfix/out/test/ramsurvey"
local frame = 0
local log = assert(io.open(outdir .. "/nmi_timing.txt", "w"))
local hist08, hist31 = {}, {}
local split_nonempty, split_frames, split_pal = 0, 0, 0
local worst08 = {}
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
local function pos()
  local s = emu.getState()
  return s["ppu.scanline"], s["ppu.cycle"]
end
local function onEntry()
  if rd(0xF0) ~= 0 then
    split_frames = split_frames + 1
    if rd(0x3F) ~= 0 and rd(0x400 + rd(0x41)) ~= 0 then split_nonempty = split_nonempty + 1 end
    if rd(0x3F) ~= 0 and rd(0x3E) ~= 0 then split_pal = split_pal + 1 end
  end
end
local function onEF08()
  local sl, cy = pos()
  local k = sl
  hist08[k] = (hist08[k] or 0) + 1
  if sl >= 250 or sl < 241 then worst08[#worst08+1] = string.format("f=%d sl=%d cy=%d", frame, sl, cy) end
end
local function onEF31()
  local sl = pos()
  hist31[sl] = (hist31[sl] or 0) + 1
end
local function dumph(name, h)
  local keys = {}
  for k in pairs(h) do keys[#keys+1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts+1] = string.format("%d:%d", k, h[k]) end
  log:write(name .. " " .. table.concat(parts, " ") .. "\n")
end
local function onFrame()
  frame = frame + 1
  if frame == 9000 then
    dumph("EF08 scanline hist", hist08)
    dumph("EF31 scanline hist", hist31)
    log:write(string.format("split frames %d, nonempty queue at entry %d, palette dirty %d\n", split_frames, split_nonempty, split_pal))
    for i = 1, math.min(#worst08, 40) do log:write("late EF08 " .. worst08[i] .. "\n") end
    log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onEntry, emu.callbackType.exec, 0xEE79, 0xEE79, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onEF08, emu.callbackType.exec, 0xEF08, 0xEF08, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onEF31, emu.callbackType.exec, 0xEF31, 0xEF31, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
