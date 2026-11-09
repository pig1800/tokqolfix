-- Where does Mesen clock the MMC3 counter?  Sample the mapper state on every
-- CPU instruction for a few frames while a message window is up.
local STATE = "D:/EMU/NES/SaveStates/rom_kanji_11.mss"
local log = assert(io.open("D:/EMU/NES/tokqolfix/out/test/canvas/ctr.txt", "w"))
local loaded, frame, lf = false, 0, nil
local keysdone = false
emu.addMemoryCallback(function()
  if loaded then return end
  loaded = true
  local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close()
  emu.loadSavestate(d); lf = frame
end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  if lf and (frame - lf == 30 or frame - lf == 70) then emu.setInput({a=true}, 0) else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)
local sampling = false
local last = nil
local lastv = nil
emu.addMemoryCallback(function()
  if not sampling then return end
  local st = emu.getState()
  if not keysdone then
    keysdone = true
    local ks = {}
    for k, v in pairs(st) do if string.find(k, "mapper") and not string.find(k, "Offset") then ks[#ks+1] = k .. "=" .. tostring(v) end end
    table.sort(ks); log:write(table.concat(ks, "\n") .. "\n")
  end
  local c = st["mapper.irqCounter"]
  local v = st["ppu.videoRamAddr"] & 0x3FFF
  local a12 = (v & 0x1000) ~= 0 and 1 or 0
  local key = tostring(c) .. "/" .. tostring(st["mapper.irqReload"])
  if key ~= last then
    log:write(string.format("f=%d par=%d sl=%d dot=%d ctr=%s reload=%s latch=%s en=%s pc=%04X v=%04X\n", frame, st["ppu.frameCount"] % 2, st["ppu.scanline"], st["ppu.cycle"], tostring(c), tostring(st["mapper.irqReload"]), tostring(st["mapper.irqReloadValue"]), tostring(st["mapper.irqEnabled"]), st["cpu.pc"], v))
    last = key
  end
end, emu.callbackType.exec, 0x0000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  frame = frame + 1
  if lf and frame - lf == 300 then sampling = true end
  if lf and frame - lf == 304 then log:close(); emu.stop(0) end
end, emu.eventType.endFrame)
