-- Screen tracer: load JT_STATE, hold-path input JT_PATH ("A3,w30,..."); frames
-- JT_L0..JT_L1: every JSR edge (bank $ED, caller, target, count, first frame)
-- and every PPU write run (address, length, writer pc, bank, first bytes).
-- JT_DUMP / JT_DUMPFILE: PPU $0000-$3FFF and internal RAM at that frame.
-- Note: PPUDATA reads advance the address but are not tracked here.
local STATE = os.getenv("JT_STATE")
local OUT = assert(io.open(os.getenv("JT_OUT"), "w"))
local L0, L1 = tonumber(os.getenv("JT_L0")), tonumber(os.getenv("JT_L1"))
local keymap = {U="up",D="down",L="left",R="right",A="a",B="b",S="start",E="select"}
local sched, total = {}, 0
for s in string.gmatch(os.getenv("JT_PATH") or "", "[^,]+") do
  local k, n = s:match("^(%a)(%d+)$"); n = tonumber(n)
  for i = 1, n do sched[total+i] = keymap[k] end; total = total + n
end
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local frame, lf, loaded = 0, nil, false
emu.addMemoryCallback(function()
  if loaded then return end
  loaded = true
  local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close()
  emu.loadSavestate(d); lf = frame
end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  local k
  if lf then local f = frame - lf; k = f >= 1 and sched[f] or nil end
  if k then local t = {}; t[k] = true; emu.setInput(t, 0) else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)
local function active() return lf and (frame - lf) >= L0 and (frame - lf) <= L1 end
local edges, order = {}, {}
emu.addMemoryCallback(function(pc)
  if not active() then return end
  if rd(pc) ~= 0x20 then return end
  local t = rd(pc + 1) | (rd(pc + 2) << 8)
  local s = emu.getState()
  local nmi = (s["ppu.scanline"] >= 241 and s["ppu.scanline"] <= 260) and "v" or "-"
  local k = string.format("%02X %04X>%04X", rd(0xED), pc, t)
  if not edges[k] then edges[k] = {n = 0, f = frame - lf}; order[#order+1] = k end
  edges[k].n = edges[k].n + 1
end, emu.callbackType.exec, 0x6000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
local latch, hi, addr, run, runpc, runaddr, runbank = 0, 0, 0, {}, 0, 0, 0
local function flush()
  if #run > 0 then
    local b = {}
    for i = 1, math.min(#run, 48) do b[i] = run[i] end
    OUT:write(string.format("  W f=%d %04X n=%d pc=%04X bank=%02X: %s\n", frame - lf, runaddr, #run, runpc, runbank, table.concat(b, " ")))
    run = {}
  end
end
emu.addMemoryCallback(function(a, v)
  local r = a & 7
  if r == 6 then
    if latch == 0 then hi = v; latch = 1 else addr = ((hi & 0x3F) << 8) | v; latch = 0; if active() then flush() end end
  elseif r == 5 then latch = latch ~ 1
  elseif r == 7 then
    if active() then
      if #run == 0 then runaddr = addr; runpc = emu.getState()["cpu.pc"]; runbank = rd(0xED) end
      run[#run+1] = string.format("%02X", v)
    end
    addr = (addr + ((rd(0xFF) & 4) ~= 0 and 32 or 1)) & 0x3FFF
  end
end, emu.callbackType.write, 0x2000, 0x3FFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function(a) if (a & 7) == 2 then latch = 0 end end, emu.callbackType.read, 0x2000, 0x3FFF, emu.memType.nesMemory, emu.cpuType.nes)
local DUMP = tonumber(os.getenv("JT_DUMP") or "-1")
emu.addEventCallback(function()
  frame = frame + 1
  if not lf then return end
  local f = frame - lf
  if active() then flush() end
  if f == DUMP then
    local t = {}
    for a = 0x0000, 0x3FFF do t[#t+1] = string.char(emu.read(a, emu.memType.nesPpuDebug)) end
    local fh = io.open(os.getenv("JT_DUMPFILE"), "wb"); fh:write(table.concat(t)); fh:close()
    local r = {}
    for a = 0, 0x7FF do r[#r+1] = string.char(rd(a)) end
    fh = io.open(os.getenv("JT_DUMPFILE") .. ".ram", "wb"); fh:write(table.concat(r)); fh:close()
  end
  if f == L1 then
    OUT:write("JSR edges (bank caller>target count first-frame):\n")
    for _, k in ipairs(order) do OUT:write(string.format("  %s x%d f=%d\n", k, edges[k].n, edges[k].f)) end
    OUT:close(); emu.stop(0)
  end
end, emu.eventType.endFrame)
