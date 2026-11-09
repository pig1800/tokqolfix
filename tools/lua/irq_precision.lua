-- Assessment probe (map-canvas scheme, 2026-11-09): how exactly does the
-- MMC3 IRQ land?  Per IRQ: the scanline/dot at irq_handler entry against
-- the window border row T; the counter reload ($C001 write) before it:
-- where (NMI arm or the IRQ's re-arm), the PPU address (A12) then, the
-- frame parity.  Standard path, 6000 frames.  Out: out/test/canvas/irq_precision.txt
local A_IRQ = 0xC6B0  -- @irq_handler@
local outdir = "D:/EMU/NES/tokqolfix/out/test/canvas"
local log = assert(io.open(outdir .. "/irq_precision.txt", "w"))
local frame = 0
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4200 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({}, 0) end
  elseif frame >= 4200 and frame < 4330 then
    if frame % 30 < 3 then emu.setInput({a=true}, 0) else emu.setInput({}, 0) end
  elseif frame >= 4330 and frame < 6000 then
    if frame % 90 < 3 then emu.setInput({a=true}, 0) else emu.setInput({}, 0) end
  else emu.setInput({}, 0) end
end
local reload = nil      -- {src, sl, cyc, a12, parity}
local hist = {}
local last_ppu_write = nil
emu.addMemoryCallback(function(addr, value)
  local st = emu.getState()
  local sl = st["ppu.scanline"]
  local v = st["ppu.videoRamAddr"] & 0x3FFF
  local src = (sl >= 0 and sl < 240) and "irq" or "nmi"
  reload = {src = src, sl = sl, cyc = st["ppu.cycle"], a12 = (v & 0x1000) ~= 0 and 1 or 0,
            par = st["ppu.frameCount"] % 2, last = last_ppu_write}
end, emu.callbackType.write, 0xC001, 0xC001, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function(addr, value)
  local st = emu.getState()
  local sl = st["ppu.scanline"]
  if sl >= 240 or sl < 0 then last_ppu_write = string.format("%d.%d", sl, st["ppu.cycle"]) end
end, emu.callbackType.write, 0x2000, 0x2007, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function()
  local st = emu.getState()
  local sl, cyc = st["ppu.scanline"], st["ppu.cycle"]
  if rd(0x176) == 0 then return end
  local T = (rd(0x177) * 8 - rd(0xFC)) % 240
  local d = sl - T
  local r = reload or {src = "?", sl = -9, cyc = 0, a12 = -1, par = -1}
  -- the arm before pre-render (261) or after (-1/0..)
  local when = (r.src == "nmi") and ((r.sl >= 241 and r.sl <= 260) and "vbl" or "pre") or r.src
  local k = string.format("arm=%s a12=%d par=%d", when, r.a12, r.par)
  hist[k] = hist[k] or {}
  hist[k][d] = (hist[k][d] or 0) + 1
  if #log == 0 then end
  reload = nil
end, emu.callbackType.exec, A_IRQ, A_IRQ, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(function()
  frame = frame + 1
  if frame == 6000 then
    local ks = {}
    for k in pairs(hist) do ks[#ks+1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do
      local ds = {}
      for d in pairs(hist[k]) do ds[#ds+1] = d end
      table.sort(ds)
      local parts = {}
      for _, d in ipairs(ds) do parts[#parts+1] = string.format("%+d:%d", d, hist[k][d]) end
      log:write(k .. "  landing line - T: " .. table.concat(parts, " ") .. "\n")
    end
    log:close(); emu.stop(0)
  end
end, emu.eventType.endFrame)
