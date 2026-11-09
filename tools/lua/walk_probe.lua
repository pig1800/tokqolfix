-- Map-canvas step 2 probe: walk from a save state and log, per frame, the
-- scroll, PPUCTRL shadow, nametable runs written ($2007) and the PCs that
-- built VRAM-queue entries ($0400 writes of an entry's first byte).
-- Env: WP_STATE (.mss), WP_PATH ("U16,w20,D16,..." hold dir N frames / wait),
--      WP_OUT (log), WP_SHOTS (dir, optional: screenshot every frame of motion)
local STATE = os.getenv("WP_STATE")
local PATH = os.getenv("WP_PATH") or ""
local OUT = os.getenv("WP_OUT") or "D:/EMU/NES/tokqolfix/out/test/vring/walk.txt"
local SHOTS = os.getenv("WP_SHOTS")
local log = assert(io.open(OUT, "w"))
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local frame, lf = 0, nil
local steps = {}
for s in string.gmatch(PATH, "[^,]+") do
  local k, n = s:match("^(%a)(%d+)$")
  steps[#steps+1] = {k = k, n = tonumber(n)}
end
local keymap = {U = "up", D = "down", L = "left", R = "right", A = "a", B = "b", S = "start", w = nil}
local sched = {}
do
  local f = 0
  for _, s in ipairs(steps) do
    for i = 1, s.n do sched[f + i] = keymap[s.k] end
    f = f + s.n
  end
  sched.len = f
end
local loaded = false
emu.addMemoryCallback(function()
  if loaded then return end
  loaded = true
  local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close()
  emu.loadSavestate(d); lf = frame
end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  if not lf then emu.setInput({}, 0); return end
  local f = frame - lf - 20
  local k = f >= 1 and sched[f] or nil
  if k then local t = {}; t[k] = true; emu.setInput(t, 0) else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)
local runs = {}
emu.addMemoryCallback(function()
  local st = emu.getState()
  local v = st["ppu.videoRamAddr"] & 0x3FFF
  if v < 0x2000 or v >= 0x3F00 then return end
  local r = runs[#runs]
  local inc = (st["ppu.control.verticalWrite"] and 32 or 1)
  if r and r.next == v then r.n = r.n + 1; r.next = v + inc
  else runs[#runs+1] = {start = v, n = 1, next = v + inc, vert = inc == 32} end
end, emu.callbackType.write, 0x2007, 0x2007, emu.memType.nesMemory, emu.cpuType.nes)
local qpcs = {}
emu.addMemoryCallback(function(addr)
  local pc = emu.getCpuState().pc
  qpcs[pc] = true
end, emu.callbackType.write, 0x0400, 0x04FF, emu.memType.nesMemory, emu.cpuType.nes)
local psx, psy, pctrl
emu.addEventCallback(function()
  frame = frame + 1
  local sx, sy, ctrl = rd(0xFD), rd(0xFC), rd(0xFF)
  if lf and frame > lf then
    local parts = {}
    for _, r in ipairs(runs) do parts[#parts+1] = string.format("%04X%s%d", r.start, r.vert and "v" or "+", r.n) end
    local pcs = {}
    for pc in pairs(qpcs) do pcs[#pcs+1] = string.format("%04X", pc) end
    table.sort(pcs)
    local moved = (sx ~= psx or sy ~= psy or ctrl ~= pctrl)
    if #parts > 0 or moved then
      log:write(string.format("f=%d sx=%02X sy=%02X ctrl=%02X pos=%02X.%02X/%02X.%02X cur=%02X.%02X/%02X.%02X: %s | q:%s\n",
        frame - lf, sx, sy, ctrl, rd(0x60), rd(0x61), rd(0x62), rd(0x63),
        rd(0x1C), rd(0x1D), rd(0x1E), rd(0x1F), table.concat(parts, " "), table.concat(pcs, ",")))
    end
    if SHOTS and moved then
      local fh = io.open(string.format("%s/f%04d.png", SHOTS, frame - lf), "wb"); fh:write(emu.takeScreenshot()); fh:close()
    end
  end
  psx, psy, pctrl = sx, sy, ctrl
  runs = {}; qpcs = {}
  if lf and frame - lf > sched.len + 60 then log:close(); emu.stop(0) end
end, emu.eventType.endFrame)
