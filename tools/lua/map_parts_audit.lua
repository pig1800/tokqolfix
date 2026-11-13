-- Map-mode R0 audit (2026-11-14, TEXT_RENDERER.md "IRQ"): every MMC3 R0 write ($8000 select 0, then
-- $8001), with its PPU line and dot.  At each NMI the frame just shown is
-- checked line by line: the page fetched for line L (R0 at line L-1 dot
-- 321 and through line L dot 256) against the parts' pages (lines 0-71: 4,
-- 72-119: 8, 120-167: 10, 168-239: 12).  Only frames that start and end in
-- map mode with rendering on (TXR_ON bit 7, ppu_mask_shadow & $18).
-- Env: as map_parts_timing.lua
local STATE = os.getenv("PB_STATE"); local END = tonumber(os.getenv("PB_END"))
local STD = os.getenv("PB_STD") == "1"
local keymap = {U="up",D="down",L="left",R="right",A="a",B="b",S="start",E="select"}
local sched, total = {}, 0
for s in string.gmatch(os.getenv("PB_PATH") or "", "[^,]+") do
  local k, n = s:match("^(%a)(%d+)$"); n = tonumber(n)
  for i = 1, n do sched[total+i] = keymap[k] end; total = total + n
end
local frame, lf, loaded = 0, nil, false
if STATE and STATE ~= "" then
  emu.addMemoryCallback(function()
    if loaded then return end
    loaded = true
    local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close(); emu.loadSavestate(d)
    local img = os.getenv("PB_RAMIMG")
    if img and img ~= "" then
      local g = io.open(img, "rb"); local b = g:read("*a"); g:close()
      for i = 1, #b do emu.write(0x7900 + i - 1, string.byte(b, i), emu.memType.nesMemory) end
    end
    lf = frame
  end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
else
  lf = 0
end
emu.addEventCallback(function()
  if STD then
    if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({start=true}, 0)
    elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({a=true}, 0)
    elseif frame >= 800 and frame < 4200 then
      local phase = math.floor((frame - 800) / 40) % 6
      if phase == 0 then emu.setInput({start=true}, 0) elseif phase == 2 then emu.setInput({a=true}, 0)
      elseif phase == 4 then emu.setInput({down=true}, 0) else emu.setInput({}, 0) end
    elseif frame >= 4200 and frame < 6000 then
      if frame % 30 < 3 then emu.setInput({a=true}, 0) elseif frame % 300 < 3 then emu.setInput({b=true}, 0) else emu.setInput({}, 0) end
    else emu.setInput({}, 0) end
    return
  end
  local k
  if lf then local f = frame - lf; k = f >= 1 and sched[f] or nil end
  if k then local t = {}; t[k] = true; emu.setInput(t, 0) else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)

local R = function(a) return emu.read(a, emu.memType.nesMemory) end
local function ppos()
  local s = emu.getState()
  local sl, dot = s["ppu.scanline"], s["ppu.cycle"]
  if sl == -1 or sl == 261 then sl = -1 elseif sl >= 241 then sl = sl - 262 end
  return sl * 341 + dot, s["cpu.pc"]
end
local sel, r0, r0start = 0, 4, 4
local writes = {}
emu.addMemoryCallback(function(addr, value)
  if (addr & 1) == 0 then sel = value & 7
  elseif sel == 0 then
    r0 = value & 0xFE
    local p, pc = ppos()
    writes[#writes+1] = {p, r0, pc}
  end
end, emu.callbackType.write, 0x8000, 0x9FFF, emu.memType.nesMemory, emu.cpuType.nes)
local function want(L)
  if L < 72 then return 4 elseif L < 120 then return 8 elseif L < 168 then return 10 else return 12 end
end
local nev, nbad, nwrong, ntorn, bad = 0, 0, 0, 0, {}
local prevok = false
local function inmap() return (R(0x0780) & 0x80) ~= 0 and (R(0xFE) & 0x18) ~= 0 end
emu.addMemoryCallback(function()
  local okn = inmap()
  if lf and prevok and okn then
    nev = nev + 1
    local function at(q)
      local v = r0start
      for _, w in ipairs(writes) do if w[1] <= q then v = w[2] else break end end
      return v
    end
    local wrong, torn, first = 0, 0, nil
    for L = 0, 239 do
      local v1 = at((L - 1) * 341 + 321)
      local v2 = at(L * 341 + 256)
      if v1 ~= v2 then torn = torn + 1; first = first or string.format("line %d torn %d/%d", L, v1, v2) end
      if v1 ~= want(L) or v2 ~= want(L) then wrong = wrong + 1; first = first or string.format("line %d page %d/%d", L, v1, v2) end
    end
    if wrong > 0 or torn > 0 then
      nbad = nbad + 1; nwrong = nwrong + wrong; ntorn = ntorn + torn
      local t = {}
      for _, w in ipairs(writes) do
        local l = w[1] // 341
        t[#t+1] = string.format("%d@%d.%d(%04X)", w[2], l, w[1] - l * 341, w[3])
      end
      if #bad < 300 then bad[#bad+1] = string.format("f%d wrong %d torn %d first %s; writes %s", frame - lf, wrong, torn, first, table.concat(t, " ")) end
    end
  end
  prevok = okn
  r0start = r0; writes = {}
end, emu.callbackType.exec, 0xEE79, 0xEE79, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  frame = frame + 1
  if lf and frame - lf == END then
    local o = io.open(os.getenv("PB_OUT"), "w")
    o:write(string.format("map frames checked %d, bad %d (wrong-page lines %d, torn lines %d)\n", nev, nbad, nwrong, ntorn))
    for _, b in ipairs(bad) do o:write(b .. "\n") end
    o:close(); emu.stop(0)
  end
end, emu.eventType.endFrame)
