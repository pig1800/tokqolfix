-- Original ROM: which PCs write PPUDATA while the PPU address is in CHR
-- ($0000-$1FFF)?  Also OAM tile-index usage and PPUMASK shadow during the
-- standard path.  Output: out/test/ramsurvey/chr_writers.txt
local outdir = "D:/EMU/NES/tokqolfix/out/test/ramsurvey"
local frame = 0
local addr_hi, addr_lo, latch = 0, 0, false
local vaddr = 0
local writers = {}
local oamtiles = {}
local masks = {}
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
local function onAddr(addr, value)
  if not latch then addr_hi = value else addr_lo = value; vaddr = ((addr_hi << 8) | addr_lo) & 0x3FFF end
  latch = not latch
end
local function onStatus(addr, value) latch = false end
local function onData(addr, value)
  if vaddr < 0x2000 then
    local pc = emu.getCpuState().pc
    local key = string.format("%04X %s", pc, vaddr < 0x1000 and "pg0" or "pg1")
    writers[key] = (writers[key] or 0) + 1
  end
  local inc = (rd(0xFF) & 0x04) ~= 0 and 32 or 1
  vaddr = (vaddr + inc) & 0x3FFF
end
local function onFrame()
  frame = frame + 1
  if frame % 5 == 0 then
    for i = 0, 63 do
      local y = rd(0x200 + i * 4)
      if y < 0xF0 then local t = rd(0x201 + i * 4); oamtiles[t] = (oamtiles[t] or 0) + 1 end
    end
    local m = rd(0xFE); masks[m] = (masks[m] or 0) + 1
  end
  if frame == 4000 then
    local f = assert(io.open(outdir .. "/chr_writers.txt", "w"))
    local keys = {}
    for k in pairs(writers) do keys[#keys+1] = k end
    table.sort(keys, function(a, b) return writers[a] > writers[b] end)
    f:write("PPUDATA writers into CHR (pc page count):\n")
    for _, k in ipairs(keys) do f:write(string.format("  %s x%d\n", k, writers[k])) end
    local unused = {}
    for t = 0, 255 do if not oamtiles[t] then unused[#unused+1] = string.format("%02X", t) end end
    f:write("OAM tile indices never used (visible sprites, sampled every 5 frames): " .. table.concat(unused, " ") .. "\n")
    f:write("PPUMASK shadow values: ")
    for m, c in pairs(masks) do f:write(string.format("%02X x%d  ", m, c)) end
    f:write("\n"); f:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onAddr, emu.callbackType.write, 0x2006, 0x2006, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onStatus, emu.callbackType.read, 0x2002, 0x2002, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onData, emu.callbackType.write, 0x2007, 0x2007, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
