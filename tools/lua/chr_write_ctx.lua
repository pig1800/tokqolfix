-- Original ROM: classify every PPUDATA write into CHR by writer PC, target
-- page, whether the PPU is rendering (mask bits 3/4 set in the shadow and
-- scanline in 0-239 or 261), NMI vs main context, and per-frame byte count.
local outdir = "D:/EMU/NES/tokqolfix/out/test/ramsurvey"
local frame = 0
local hi, lo, latch, vaddr = 0, 0, false, 0
local in_nmi = false
local stats = {}
local perframe, maxframe, maxf = 0, 0, 0
local tiles_by_pc = {}
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
local function onAddr(addr, value)
  if not latch then hi = value else lo = value; vaddr = ((hi << 8) | lo) & 0x3FFF end
  latch = not latch
end
local function onStatus() latch = false end
local function onData(addr, value)
  if vaddr < 0x2000 then
    local pc = emu.getCpuState().pc
    local s = emu.getState()
    local sl = s["ppu.scanline"]
    local rend = (rd(0xFE) & 0x18) ~= 0
    local key = string.format("pc=%04X page=%d ctx=%s busy=%d rend_shadow=%s", pc, vaddr >> 12, in_nmi and "nmi" or "main", rd(0xEC), tostring(rend))
    stats[key] = (stats[key] or 0) + 1
    if vaddr >= 0x1000 then perframe = perframe + 1 end
  end
  local inc = (rd(0xFF) & 0x04) ~= 0 and 32 or 1
  vaddr = (vaddr + inc) & 0x3FFF
end
local function onFrame()
  frame = frame + 1
  if perframe > maxframe then maxframe = perframe; maxf = frame end
  perframe = 0
  if frame == 9000 then
    local f = assert(io.open(outdir .. "/chr_write_ctx.txt", "w"))
    local keys = {}
    for k in pairs(stats) do keys[#keys+1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do f:write(string.format("%s x%d\n", k, stats[k])) end
    f:write(string.format("max page-1 bytes in one frame: %d at f=%d\n", maxframe, maxf))
    f:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(function() in_nmi = true end, emu.callbackType.exec, 0xEE79, 0xEE79, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function() in_nmi = false end, emu.callbackType.exec, 0xEF37, 0xEF37, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onAddr, emu.callbackType.write, 0x2006, 0x2006, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onStatus, emu.callbackType.read, 0x2002, 0x2002, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onData, emu.callbackType.write, 0x2007, 0x2007, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
