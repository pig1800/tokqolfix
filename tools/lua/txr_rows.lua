-- Map text renderer assessment (TEXT_RENDERER.md), 2026-11-12.
-- Survey: every nametable write of a tile < $80 in map mode (input_buttons
-- bit 7 clear): screen row (60-row ring, top = ctrl bit 1 * 30 + scroll_y/8),
-- frame-corner tiles' rows, scroll_y mod 16.  Env: PB_STATE, PB_PATH, PB_END, PB_OUT
local STATE = os.getenv("PB_STATE")
local OUT = os.getenv("PB_OUT")
local END = tonumber(os.getenv("PB_END"))
local keymap = {U="up",D="down",L="left",R="right",A="a",B="b",S="start",E="select"}
local sched, total = {}, 0
for s in string.gmatch(os.getenv("PB_PATH") or "", "[^,]+") do
  local k, n = s:match("^(%a)(%d+)$"); n = tonumber(n)
  for i = 1, n do sched[total+i] = keymap[k] end; total = total + n
end
local frame, lf, loaded = 0, nil, false
emu.addMemoryCallback(function()
  if loaded then return end
  loaded = true
  if STATE and STATE ~= "" then
    local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close(); emu.loadSavestate(d)
  end
  lf = frame
end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  local k
  if lf then local f = frame - lf; k = f >= 1 and sched[f] or nil end
  if k then local t = {}; t[k] = true; emu.setInput(t, 0) else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local latch, hi, va, ctrl = false, 0, 0, 0
local rows, corner, odd16, mapw, nonmap = {}, {}, 0, 0, 0
local cornerT = {[0x6D]="TL",[0x6E]="TR",[0x0B]="BL",[0x6F]="BR"}
emu.addMemoryCallback(function(addr, value)
  if addr == 0x2000 then ctrl = value
  elseif addr == 0x2006 then
    if not latch then hi = value & 0x3F else va = (hi << 8) | value end
    latch = not latch
  elseif addr == 0x2007 then
    local a = va
    va = (va + (((ctrl & 4) ~= 0) and 32 or 1)) & 0x3FFF
    if a >= 0x2000 and a < 0x3000 and (a & 0x3FF) < 0x3C0 and value < 0x80 then
      if (rd(0x58) & 0x80) ~= 0 then nonmap = nonmap + 1; return end
      mapw = mapw + 1
      local t = (a >> 10) & 3
      local ntrow = ((t >> 1) * 30) + ((a & 0x3FF) >> 5)
      local sy = rd(0xFC); local sc = rd(0xFF)
      if sy % 16 ~= 0 then odd16 = odd16 + 1 end
      local top = (((sc & 2) ~= 0) and 30 or 0) + (sy >> 3)
      local srow = (ntrow - top) % 60
      rows[srow] = (rows[srow] or 0) + 1
      local c = cornerT[value]
      if c then local key = c .. ":" .. srow; corner[key] = (corner[key] or 0) + 1 end
    end
  elseif addr == 0x2002 then latch = false end
end, emu.callbackType.write, 0x2000, 0x2007, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function() latch = false end, emu.callbackType.read, 0x2002, 0x2002, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  frame = frame + 1
  if lf and frame - lf == END then
    local fh = io.open(OUT, "w")
    fh:write(string.format("map text writes %d, non-map %d, scroll_y not mult of 16: %d\n", mapw, nonmap, odd16))
    local ks = {}; for k in pairs(rows) do ks[#ks+1] = k end; table.sort(ks)
    for _, k in ipairs(ks) do fh:write(string.format("row %2d: %d\n", k, rows[k])) end
    ks = {}; for k in pairs(corner) do ks[#ks+1] = k end; table.sort(ks)
    for _, k in ipairs(ks) do fh:write(string.format("corner %s: %d\n", k, corner[k])) end
    fh:close(); emu.stop(0)
  end
end, emu.eventType.endFrame)
