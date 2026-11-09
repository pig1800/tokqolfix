-- Revision-12 gate: the game's scroll/mask restore (loc_EECE) must stay inside vblank in
-- NMIs that upload a CHR-animation step ($39 moves); the original reaches scanline 259.
-- Scanline of the game's scroll/mask restore (loc_EECE) in NMIs that run the
-- CHR animation upload ($39 changes), and in all other rendering NMIs.
local LAST = 6000
local frame = 0
local log = assert(io.open("D:/EMU/NES/tokqolfix/out/test/r12/anim_timing.txt", "w"))
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
  elseif f >= 4330 then
    if f % 90 < 3 then emu.setInput({a=true}, 0) else emu.setInput({}, 0) end
  else emu.setInput({}, 0) end
end
local s39 = 0
local H = {anim={}, other={}}
local late = {}
local function onNmi() s39 = rd(0x39) end
local function onEECE()
  local s = emu.getState()
  local sl = s["ppu.scanline"]; if sl < 100 then sl = sl + 262 end
  if (rd(0xFE) & 0x18) == 0 or rd(0xEC) ~= 0 then return end
  local k = (rd(0x39) ~= s39) and "anim" or "other"
  H[k][sl] = (H[k][sl] or 0) + 1
  if sl >= 260 and #late < 20 then late[#late+1] = string.format("f=%d %s sl=%d.%d", frame, k, sl, s["ppu.cycle"]) end
end
local function onFrame()
  frame = frame + 1
  if frame == LAST then
    for k, h in pairs(H) do
      local ks = {}
      for sl in pairs(h) do ks[#ks+1] = sl end
      table.sort(ks)
      local parts = {}
      for _, sl in ipairs(ks) do parts[#parts+1] = sl .. ":" .. h[sl] end
      log:write(k .. ": " .. table.concat(parts, " ") .. string.char(10))
    end
    for _, l in ipairs(late) do log:write("late " .. l .. string.char(10)) end
    log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onNmi, emu.callbackType.exec, 0xEE79, 0xEE79, emu.cpuType.nes, emu.memType.nesMemory)
emu.addMemoryCallback(onEECE, emu.callbackType.exec, 0xEECE, 0xEECE, emu.cpuType.nes, emu.memType.nesMemory)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
