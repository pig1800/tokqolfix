-- Map-canvas step 3 gate: the dialogue canvas.  Per frame that shows canvas
-- rows (CV_ROWS at the frame's start):
--  (1) stage 1's second $2006 write (cv_w1) lands in line 143 at dots
--      257-320 (the PPU copies nothing from t before line 144's fetches),
--      stage 2's (cv_w2) in line 143 + 8 * rows, dots 257-320; a shown
--      canvas without both writes is "missing";
--  (2) every canvas cell with a map tile ($80 and up) equals the visible
--      half's cell at the same screen position (tile and palette): the
--      flanks beside the window are the map;
--  (3) the visible half's band rows hold no window tiles (below $80)
--      while the canvas shows: the window went to the canvas.
-- Input: CC_STATE (.mss) + CC_PATH (one step per 40 frames, "w" = wait;
-- or "U16,w30,A3" holds with CC_HOLD=1), or CC_BOOT (power on with the
-- run's battery save, buttons "300start,420a,..") + CC_PATH holds from
-- frame CC_START.  CC_FRAMES, CC_OUT.
local A_W1 = 0x7952  -- @cv_w1@
local A_W2 = 0x798F  -- @cv_w2@
local A_FORCE_END = 0x7ADF  -- @cv_force_end@
local A_RELOAD = 0x7AEC  -- @cv_reload@
local A_SFORCE_END = 0x7A61  -- @cv_sforce_end@
local A_SRELOAD = 0x7A66  -- @cv_sreload@
local CV_ROWS = 0x0783
local OUT = os.getenv("CC_OUT")
local FRAMES = tonumber(os.getenv("CC_FRAMES") or "3000")
local log = assert(io.open(OUT, "w"))
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuDebug) end
local frame, lf = 0, nil
local keymap = {U = "up", D = "down", L = "left", R = "right", A = "a", B = "b", S = "start", E = "select"}
local sched, total = {}, 0
local PATH = os.getenv("CC_PATH") or ""
local HOLD = os.getenv("CC_HOLD") or os.getenv("CC_BOOT")
if HOLD then
  for s in string.gmatch(PATH, "[^,]+") do
    local k, n = s:match("^(%a)(%d+)$"); n = tonumber(n)
    for i = 1, n do sched[total + i] = keymap[k] end
    total = total + n
  end
end
local steps = {}
for s in string.gmatch(PATH, "[^,]+") do steps[#steps+1] = s end
local STATE = os.getenv("CC_STATE")
local BOOT = os.getenv("CC_BOOT")
local boot = {}
for s in string.gmatch(BOOT or "", "[^,]+") do local f, k = s:match("^(%d+)(%a+)$"); boot[tonumber(f)] = k end
local START = tonumber(os.getenv("CC_START") or "900")
if STATE then
  local loaded = false
  emu.addMemoryCallback(function()
    if loaded then return end
    loaded = true
    local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close()
    emu.loadSavestate(d); lf = frame
  end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
else
  lf = 0
end
-- No CC_STATE / CC_BOOT: the gates' standard path (title, a new game's
-- opening, town messages), as band_check.lua.
local function stdInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then return "start"
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then return "a"
  elseif frame >= 800 and frame < 4200 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then return "start" elseif phase == 2 then return "a" elseif phase == 4 then return "down" end
  elseif frame >= 4200 and frame < 4330 then
    if frame % 30 < 3 then return "a" end
  elseif frame >= 4330 then
    if frame % 90 < 3 then return "a" end
  end
  return nil
end
emu.addEventCallback(function()
  local k
  if not BOOT and not STATE then
    k = stdInput()
  elseif BOOT then
    k = boot[frame] or boot[frame - 1] or boot[frame - 2]
    if not k and frame > START then k = sched[frame - START] end
  elseif STATE and lf then
    local f = frame - lf - 30
    if HOLD then k = f >= 1 and sched[f] or nil
    elseif f >= 0 then
      local s = steps[math.floor(f / 40) + 1]
      if s and s ~= "w" and (f % 40) < 3 then k = s end
    end
  end
  if k then local t = {}; t[k] = true; emu.setInput(t, 0) else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)

local rows_now = 0        -- CV_ROWS when the frame started rendering
local w1, w2 = nil, nil
local n_frames, n_missing, n_w1_bad, n_w2_bad = 0, 0, 0, 0
local n_flank, n_flank_bad, n_vis_win = 0, 0, 0
local ex = {}
local function note(s) if #ex < 40 then ex[#ex+1] = s end end
emu.addMemoryCallback(function()
  local s = emu.getState()
  w1 = {sl = s["ppu.scanline"], dot = s["ppu.cycle"], rows = rd(CV_ROWS)}
end, emu.callbackType.exec, A_W1, A_W1, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function()
  local s = emu.getState()
  w2 = {sl = s["ppu.scanline"], dot = s["ppu.cycle"]}
end, emu.callbackType.exec, A_W2, A_W2, emu.memType.nesMemory, emu.cpuType.nes)
-- cv_nmi's force must end by pre-render dot 256 (the PPU copies t back to
-- v at dots 257 and 280-304) and its counter reload must come before the
-- pre-render line's clock (dot ~325): any frame, canvas or not.
local n_force, n_force_late, n_reload_late = 0, 0, 0
local force_last = "none"
emu.addMemoryCallback(function()
  local s = emu.getState()
  local sl, dot = s["ppu.scanline"], s["ppu.cycle"]
  n_force = n_force + 1
  if sl < 0 or sl > 260 then force_last = string.format("pre-render dot %d", dot) end
  if (sl >= 0 and sl < 241) or ((sl < 0 or sl > 260) and dot > 256) then
    n_force_late = n_force_late + 1
    note(string.format("f=%d force ends at %d.%d", frame, sl, dot))
  end
end, emu.callbackType.exec, A_FORCE_END, A_FORCE_END, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function()
  local s = emu.getState()
  local sl, dot = s["ppu.scanline"], s["ppu.cycle"]
  if (sl >= 0 and sl < 241) or ((sl < 0 or sl > 260) and dot > 300) then
    n_reload_late = n_reload_late + 1
    note(string.format("f=%d canvas reload at %d.%d", frame, sl, dot))
  end
end, emu.callbackType.exec, A_RELOAD, A_RELOAD, emu.memType.nesMemory, emu.cpuType.nes)
-- The same two deadlines on the CHR-stream path (cv_stream: right after
-- the game's stream step, the game's NMI goes on past the pre-render line).
local n_sforce = 0
emu.addMemoryCallback(function()
  local s = emu.getState()
  local sl, dot = s["ppu.scanline"], s["ppu.cycle"]
  n_sforce = n_sforce + 1
  if (sl >= 0 and sl < 241) or ((sl < 0 or sl > 260) and dot > 256) then
    n_force_late = n_force_late + 1
    note(string.format("f=%d stream force ends at %d.%d", frame, sl, dot))
  end
end, emu.callbackType.exec, A_SFORCE_END, A_SFORCE_END, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function()
  local s = emu.getState()
  local sl, dot = s["ppu.scanline"], s["ppu.cycle"]
  if (sl >= 0 and sl < 241) or ((sl < 0 or sl > 260) and dot > 300) then
    n_reload_late = n_reload_late + 1
    note(string.format("f=%d stream reload at %d.%d", frame, sl, dot))
  end
end, emu.callbackType.exec, A_SRELOAD, A_SRELOAD, emu.memType.nesMemory, emu.cpuType.nes)
-- Bytes the game's flush wrote in the frame's NMI (flush_vram_queue $D9A1..$D9EC).
local q0, qbytes = 0, 0
emu.addMemoryCallback(function() q0 = rd(0x41) end, emu.callbackType.exec, 0xD9A1, 0xD9A1, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function() qbytes = (rd(0x41) - q0) & 0xFF end, emu.callbackType.exec, 0xD9EC, 0xD9EC, emu.memType.nesMemory, emu.cpuType.nes)
-- The frame starts at the pre-render line: take CV_ROWS there.
local qframe = 0
emu.addEventCallback(function()
  rows_now = rd(CV_ROWS)
  w1, w2 = nil, nil
  qframe = qbytes; qbytes = 0
end, emu.eventType.startFrame)

-- Cell (tile, palette) at a nametable address.
local function cell(addr)
  local base = addr & 0xFC00
  local off = addr & 0x3FF
  local row, col = off >> 5, off & 31
  local t = ppu(addr)
  local at = ppu(base + 0x3C0 + (row >> 2) * 8 + (col >> 2))
  return t, (at >> (((row & 2) << 1) | (col & 2))) & 3
end

emu.addEventCallback(function()
  frame = frame + 1
  if not lf or frame <= lf then return end
  local f = frame - lf
  -- the height the frame's split used (CV_ROWS at stage 1; cv_nmi may run
  -- after the frame's start event in a long frame)
  local rows = w1 and w1.rows or math.min(rows_now, rd(CV_ROWS))
  if rows > 0 and rd(0xEC) == 0 and (rd(0xFE) & 0x18) ~= 0 then
    n_frames = n_frames + 1
    -- (1) split timing; the store's write cycle is its last (+3 CPU cycles
    -- = +9 dots after the instruction's first cycle)
    if not w1 or not w2 then
      n_missing = n_missing + 1
      note(string.format("f=%d rows=%d missing stage %s", f, rows, w1 and "2" or "1"))
    else
      local d1, d2 = w1.dot + 9, w2.dot + 9
      if w1.sl ~= 143 or d1 < 257 or d1 > 320 then
        n_w1_bad = n_w1_bad + 1
        note(string.format("f=%d rows=%d stage 1 write at %d.%d (flush %d bytes)", f, rows, w1.sl, d1, qframe))
      end
      if w2.sl ~= 143 + 8 * rows or d2 < 257 or d2 > 320 then
        n_w2_bad = n_w2_bad + 1
        note(string.format("f=%d rows=%d stage 2 write at %d.%d", f, rows, w2.sl, d2))
      end
    end
    -- (2)/(3) cells of the canvas rows against the visible half
    local sx, sy, ctrl = rd(0xFD), rd(0xFC), rd(0xFF)
    local cx0 = (sx >> 3) + (ctrl & 1) * 32
    local cy0 = (sy >> 3) + ((ctrl >> 1) & 1) * 30
    for r = 0, rows - 1 do
      local ty = (cy0 + 18 + r) % 60
      local vbase = 0x2000 + (ty >= 30 and 0x800 or 0)
      local row = ty % 30
      for c = 0, 31 do
        local tx = (cx0 + c) % 64
        local a = vbase + (tx >= 32 and 0x400 or 0) + row * 32 + (tx % 32)
        local vt, vp = cell(a)
        local ct, cp = cell(a ~ 0x800)
        if ct >= 0x80 then
          n_flank = n_flank + 1
          if ct ~= vt or cp ~= vp then
            n_flank_bad = n_flank_bad + 1
            note(string.format("f=%d screen(%d,%d) canvas %02X.%d visible %02X.%d", f, c, 18 + r, ct, cp, vt, vp))
          end
        end
        if vt < 0x80 then
          n_vis_win = n_vis_win + 1
          note(string.format("f=%d screen(%d,%d) visible half has tile %02X", f, c, 18 + r, vt))
        end
      end
    end
  end
  if f >= FRAMES then
    log:write(string.format("canvas frames %d, missing splits %d, stage 1 off %d, stage 2 off %d\n", n_frames, n_missing, n_w1_bad, n_w2_bad))
    log:write(string.format("canvas map cells %d, unlike the visible map %d; window tiles in the visible band rows %d\n", n_flank, n_flank_bad, n_vis_win))
    log:write(string.format("cv_nmi forces %d, stream forces %d, late %d (latest in the pre-render line: %s); canvas reloads late %d\n", n_force, n_sforce, n_force_late, force_last, n_reload_late))
    for _, e in ipairs(ex) do log:write("  " .. e .. "\n") end
    log:close(); emu.stop(0)
  end
end, emu.eventType.endFrame)
