-- Revision-11 diagnostic on the standard path + town: band switch scanline
-- (MMC3 R0 data writes since revision 21: value / 4 = page of BG tiles
-- $00-$7F), hit/miss flags, PPU data access while rendering by non-game
-- code, crash detector, screenshots.
local outdir = "D:/EMU/NES/tokqolfix/out/test/r11"
local frame = 0
local log = assert(io.open(outdir .. "/diag.txt", "w"))
local n1 = 0
local switches = {}
local hist = {}
local hits, misses, bandframes = 0, 0, 0
local bad_ppu = 0
local badlog = {}
local crash = nil
local msgs = {}
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
  elseif frame >= 4330 and frame < 6000 then
    if frame % 90 < 3 then emu.setInput({a=true}, 0) else emu.setInput({a=false}, 0) end
  else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
end
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function st() return emu.getState() end
local sel = 0
local function onChr1(addr, value)
  if (addr & 0xE001) == 0x8000 then sel = value; return end
  if (addr & 0xE001) ~= 0x8001 or (sel & 7) ~= 0 then return end
  n1 = n1 + 1
  local s = st()
  switches[#switches+1] = string.format("%d:%d@%04X", s["ppu.scanline"], value // 4, emu.getCpuState().pc)
end
local function onPpu(addr, value)
  local s = st()
  local sl = s["ppu.scanline"]
  local mask = s["ppu.mask.backgroundEnabled"] or s["ppu.mask.spritesEnabled"]
  if (sl >= 0 and sl < 240) or sl == 261 or sl == -1 then
    local bg = s["ppu.mask.backgroundEnabled"]
    local sp = s["ppu.mask.spritesEnabled"]
    if bg or sp then
      local pc = emu.getCpuState().pc
      if not (pc >= 0xEF40 and pc <= 0xEFD0) then
        bad_ppu = bad_ppu + 1
        if #badlog < 30 then badlog[#badlog+1] = string.format("f=%d sl=%d %04X pc=%04X", frame, sl, addr, pc) end
      end
    end
  end
end
local function onBad(addr)
  if crash then return end
  crash = string.format("f=%d exec %04X", frame, addr)
end
local function onMsg() msgs[#msgs+1] = frame end
local function onFrame()
  frame = frame + 1
  local band = rd(0x176)
  if band ~= 0 then
    bandframes = bandframes + 1
    local fl = rd(0x17B)
    if (fl & 0x40) ~= 0 then hits = hits + 1 end
    if (fl & 0x80) ~= 0 then misses = misses + 1 end
  end
  for _, sw in ipairs(switches) do
    local sl, v = sw:match("^(-?%d+):(%d+)")
    if v == "2" then local k = tonumber(sl); hist[k] = (hist[k] or 0) + 1 end
  end
  if band ~= 0 or frame % 100 == 0 then
    log:write(string.format("f=%d band=%d fl=%02X row=%d col=%02X A0=%02X st=%02X req=%d sw=%s\n", frame, band, rd(0x17B), rd(0x177), rd(0x178), rd(0x140), rd(0x150), rd(0x174), table.concat(switches, " ")))
  end
  switches = {}
  if frame % 20 == 0 and frame >= 600 then
    local f = assert(io.open(string.format("%s/f%04d.png", outdir, frame), "wb")); f:write(emu.takeScreenshot()); f:close()
  end
  if frame == 6000 or crash then
    log:write("SUMMARY\n")
    log:write("messages at frames: " .. table.concat(msgs, " ") .. "\n")
    log:write(string.format("band frames %d, hit flags %d, miss flags %d\n", bandframes, hits, misses))
    local ks = {}
    for k in pairs(hist) do ks[#ks+1] = k end
    table.sort(ks)
    local parts = {}
    for _, k in ipairs(ks) do parts[#parts+1] = string.format("%d:%d", k, hist[k]) end
    log:write("band switch (page 2) scanlines: " .. table.concat(parts, " ") .. "\n")
    log:write(string.format("PPU accesses during rendering outside the split code: %d\n", bad_ppu))
    for _, b in ipairs(badlog) do log:write("  " .. b .. "\n") end
    if crash then log:write("CRASH " .. crash .. "\n") end
    log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onChr1, emu.callbackType.write, 0x8000, 0x9FFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onPpu, emu.callbackType.write, 0x2006, 0x2007, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onPpu, emu.callbackType.read, 0x2007, 0x2007, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onBad, emu.callbackType.exec, 0x0800, 0x5FFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onBad, emu.callbackType.exec, 0x0000, 0x05FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onBad, emu.callbackType.exec, 0x0700, 0x07FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onMsg, emu.callbackType.exec, 0xD124, 0xD124, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
