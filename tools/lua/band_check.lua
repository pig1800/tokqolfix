-- Revision-11 gate: on every band frame, (1) the CHR-register-1 switch to
-- the band page lands on the window's top border row (scanlines
-- band_y .. band_y+7), and (2) every tile shown on the band rows has the
-- same CHR on page 1 and page 2 unless it is an active kanji slot.
-- MMC3 (revision 21): only tiles $00-$7F come from the band page (R0);
-- $80-$FF always show the scene page and are not compared.
-- Standard path + town, 6000 frames.  Output: out/test/r11/band_check.txt
local A_SWITCHED = 0xC6AA  -- @irq_switched@
local outdir = "D:/EMU/NES/tokqolfix/out/test/r11"
local frame = 0
local log = assert(io.open(outdir .. "/band_check.txt", "w"))
local switch_sl = nil
local sw_hist, sw_bad = {}, 0
local frames_checked, frames_bad, cells_bad = 0, 0, 0
local examples = {}
local conflicts, cex = 0, {}
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function onBuf(addr, value)
  local pc = emu.getCpuState().pc
  if pc >= 0xB800 and pc < 0xC000 then return end      -- overlay (kanji tiles)
  if pc >= 0xD405 and pc <= 0xD43A then return end      -- scroll copies existing tiles
  if value >= 0x80 or rd(0x176) == 0 then return end
  local bit = 0x80 >> (value & 7)
  if (rd(0x140 + (value >> 3)) & bit) ~= 0 then
    conflicts = conflicts + 1
    if #cex < 20 then cex[#cex+1] = string.format("f=%d pc=%04X buf=%04X tile=%02X", frame, pc, addr, value) end
  end
end
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
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local function chr(a) return emu.read(a, emu.memType.nesChrRam) end
local function hm() return rd(0x8000) == 0x4C and rd(0x8003) == 0x4C and rd(0x8006) == 0x4C end
local function onSwitch()
  switch_sl = emu.getState()["ppu.scanline"]   -- fixed bank (IRQ)
end
local function onFrame()
  frame = frame + 1
  local band = rd(0x176)
  local sl = switch_sl
  switch_sl = nil
  if band ~= 0 and sl then
    local row, sy = rd(0x177) & 0x1F, rd(0xFC)
    local band_y = (row * 8 - sy) % 240
    local d = sl - band_y
    sw_hist[d] = (sw_hist[d] or 0) + 1
    if d < 0 or d > 7 then sw_bad = sw_bad + 1 end
    -- shadow check over the visible band rows
    frames_checked = frames_checked + 1
    local sx = rd(0xFD)
    local ctrl = rd(0xFF)
    local ntx = ctrl & 1
    local bad = 0
    for y = band_y, 239, 8 do
      local wy = (y + sy + ((ctrl >> 1) & 1) * 240) % 480   -- four-screen ring
      local vnt = wy >= 240 and 0x800 or 0
      local trow = math.floor((wy % 240) / 8)
      for x = 0, 255, 8 do
        local wx = x + sx + ntx * 256
        local nt = math.floor(wx / 256) % 2
        local tcol = math.floor((wx % 256) / 8)
        local t = ppu(0x2000 + vnt + nt * 0x400 + trow * 32 + tcol)
        local active = false
        if t < 0x80 then
          local bit = 0x80 >> (t & 7)
          active = (rd(0x140 + (t >> 3)) & bit) ~= 0
        end
        if not active and t < 0x80 then
          for i = 0, 15 do
            if chr(0x1000 + t * 16 + i) ~= chr(0x2000 + t * 16 + i) then
              bad = bad + 1
              if #examples < 40 then examples[#examples+1] = string.format("f=%d screen(%d,%d) tile=%02X", frame, x, y, t) end
              break
            end
          end
        end
      end
    end
    if bad > 0 then frames_bad = frames_bad + 1; cells_bad = cells_bad + bad end
  end
  if frame == 6000 then
    local ks = {}
    for k in pairs(sw_hist) do ks[#ks+1] = k end
    table.sort(ks)
    local parts = {}
    for _, k in ipairs(ks) do parts[#parts+1] = string.format("%+d:%d", k, sw_hist[k]) end
    log:write("switch scanline minus band top: " .. table.concat(parts, " ") .. "\n")
    log:write(string.format("switches outside the border row: %d\n", sw_bad))
    log:write(string.format("band frames checked %d, frames with page-2 mismatches %d, mismatching cells %d\n", frames_checked, frames_bad, cells_bad))
    for _, e in ipairs(examples) do log:write("  " .. e .. "\n") end
    log:write(string.format("kana written over an active kanji tile: %d\n", conflicts))
    for _, e in ipairs(cex) do log:write("  " .. e .. "\n") end
    log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onBuf, emu.callbackType.write, 0x0300, 0x03BF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onSwitch, emu.callbackType.exec, A_SWITCHED, A_SWITCHED, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
