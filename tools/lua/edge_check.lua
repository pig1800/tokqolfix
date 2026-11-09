-- Map-canvas step 2 gate: while the camera moves, every map cell on screen
-- (all 240 lines, overscan included) must show what the same world cell
-- shows when the camera rests before or after the step.  World position
-- from the player (text_y:text_x, text_y2:text_x2) and the scroll.
-- Env: EC_STATE (.mss), EC_PATH ("U16,w30,..."), EC_FRAMES, EC_OUT,
-- EC_RING (480: four-screen, 240: two-screen build).
local STATE = os.getenv("EC_STATE")
local PATH = os.getenv("EC_PATH") or ""
local FRAMES = tonumber(os.getenv("EC_FRAMES") or "2000")
local OUT = os.getenv("EC_OUT")
local RING = tonumber(os.getenv("EC_RING") or "480")
local log = assert(io.open(OUT, "w"))
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuDebug) end
local frame, lf = 0, nil
local keymap = {U = "up", D = "down", L = "left", R = "right", A = "a", B = "b", S = "start", E = "select"}
local sched, total = {}, 0
for s in string.gmatch(PATH, "[^,]+") do
  local k, n = s:match("^(%a)(%d+)$"); n = tonumber(n)
  for i = 1, n do sched[total + i] = keymap[k] end
  total = total + n
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
  local f = frame - lf - 10
  local k = f >= 1 and sched[f] or nil
  if k then local t = {}; t[k] = true; emu.setInput(t, 0) else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)
local function smod(v, m) v = v % m; if v >= m // 2 then v = v - m end; return v end
local function camera()
  local sx, sy, ctrl = rd(0xFD), rd(0xFC), rd(0xFF)
  local top = (rd(0x61) * 15 + rd(0x60) - 7) * 16
  local left = (rd(0x63) * 16 + rd(0x62) - 8) * 16
  local cur_y = (RING == 480 and ((ctrl >> 1) & 1) * 240 or 0) + sy
  local cy = top + smod(cur_y - top % RING, RING)
  local cur_x = (ctrl & 1) * 256 + sx
  local cx = left + smod(cur_x - left % 512, 512)
  return cx, cy, sx, sy, ctrl
end
local function cell(wx, wy)
  local ry, rx = wy % 60, wx % 64
  local base = 0x2000 + (ry >= 30 and 0x800 or 0) + (rx >= 32 and 0x400 or 0)
  local row, col = ry % 30, rx % 32
  local t = ppu(base + row * 32 + col)
  local at = ppu(base + 0x3C0 + (row >> 2) * 8 + (col >> 2))
  return t * 4 + ((at >> (((row & 2) << 1) | (col & 2))) & 3)
end
local function view(cx, cy)
  local v = {}
  for wy = cy // 8, (cy + 239) // 8 do
    local y0 = wy * 8 - cy
    local area = (y0 + 7 < 8 or y0 > 231) and "o" or "p"   -- overscan / picture
    for wx = cx // 8, (cx + 255) // 8 do
      v[wy * 4096 + wx] = {cell(wx, wy), area}
    end
  end
  return v
end
local prev_key, rest_view, pending = nil, nil, {}
local prev_cx, prev_cy = nil, nil
local bad = {o = 0, p = 0}; local checked = 0; local ex = {}
local function compare(mv, rv, f)
  for k, c in pairs(mv) do
    local r = rv[k]
    if r then
      checked = checked + 1
      if r[1] ~= c[1] then
        bad[c[2]] = bad[c[2]] + 1
        if #ex < 30 then ex[#ex + 1] = string.format("f=%d world(%d,%d) %s %03X vs rest %03X", f, k % 4096, k // 4096, c[2], c[1], r[1]) end
      end
    end
  end
end
local moving_frames = 0
emu.addEventCallback(function()
  frame = frame + 1
  if not lf or frame <= lf + 5 then return end
  local f = frame - lf
  local cx, cy, sx, sy, ctrl = camera()
  local key = string.format("%d,%d", cx, cy)
  if prev_cx and (math.abs(cx - prev_cx) > 16 or math.abs(cy - prev_cy) > 16) then
    rest_view, pending, prev_key = nil, {}, nil   -- a cut (new map, warp): no step
  end
  prev_cx, prev_cy = cx, cy
  local rest = (sx % 16 == 0) and (sy % 16 == 0) and key == prev_key
  if rest and rd(0x176) == 0 then
    local v = view(cx, cy)
    for _, p in ipairs(pending) do compare(p.v, v, p.f) end
    pending = {}
    rest_view = v
  elseif key ~= prev_key and prev_key then
    moving_frames = moving_frames + 1
    local v = view(cx, cy)
    if rest_view then compare(v, rest_view, f) end
    pending[#pending + 1] = {v = v, f = f}
  end
  prev_key = key
  if f >= FRAMES then
    log:write(string.format("moving frames %d, cells compared %d, mismatches: picture %d, overscan %d\n", moving_frames, checked, bad.p, bad.o))
    for _, e in ipairs(ex) do log:write("  " .. e .. "\n") end
    log:close(); emu.stop(0)
  end
end, emu.eventType.endFrame)
