-- Map-canvas step 1 gate: does the scanline IRQ land on one exact line?
-- Per band frame: the stage-0 handler's line/dot (must be line 0, after
-- dot 5), the stage-1 switch line minus T (T = window border row's first
-- line), the arm ($C001 write in vblank) time, the frame parity and the
-- queue bytes the game flushed.  Standard path (or IP_STATE + IP_PATH),
-- IP_FRAMES frames.  Out: IP_OUT (default out/test/canvas/irq_precision.txt)
local A_ST0 = 0x7900  -- @cv_irq@
local A_SW  = 0xC6A0  -- @irq_switched@
local STATE = os.getenv("IP_STATE")
local PATH = os.getenv("IP_PATH") or ""
local FRAMES = tonumber(os.getenv("IP_FRAMES") or "6000")
local OUT = os.getenv("IP_OUT") or "D:/EMU/NES/tokqolfix/out/test/canvas/irq_precision.txt"
local log = assert(io.open(OUT, "w"))
local frame, lf = 0, nil
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local steps = {}
for s in string.gmatch(PATH, "[^,]+") do steps[#steps+1] = s end
if STATE then
  local loaded = false
  emu.addMemoryCallback(function()
    if loaded then return end
    loaded = true
    local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close()
    emu.loadSavestate(d); lf = frame
  end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
end
local function stdInput()
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
emu.addEventCallback(function()
  if not STATE then stdInput(); return end
  if not lf then emu.setInput({}, 0); return end
  local f = frame - lf - 30
  if f < 0 then emu.setInput({}, 0); return end
  local s = steps[math.floor(f / 40) + 1]
  if s and s ~= "w" and (f % 40) < 3 then local t = {}; t[s] = true; emu.setInput(t, 0)
  else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)
local function hist_add(h, k, v) h[k] = h[k] or {}; h[k][v] = (h[k][v] or 0) + 1 end
local arm, st0 = nil, nil
local qpos_prev = rd(0x41)
local h_sw, h_st0, h_arm = {}, {}, {}
local n_sw, n_st0 = 0, 0
local bad = {}
emu.addMemoryCallback(function()
  local st = emu.getState()
  local sl = st["ppu.scanline"]
  if sl >= 240 or sl < 0 then
    arm = {sl = sl, dot = st["ppu.cycle"], par = st["ppu.frameCount"] % 2}
  end
end, emu.callbackType.write, 0xC001, 0xC001, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function()
  local st = emu.getState()
  st0 = {sl = st["ppu.scanline"], dot = st["ppu.cycle"]}
  n_st0 = n_st0 + 1
  hist_add(h_st0, "stage0 line", st0.sl)
  if st0.sl ~= 0 or st0.dot < 6 then
    if #bad < 30 then bad[#bad+1] = string.format("f=%d stage0 at %d.%d", frame, st0.sl, st0.dot) end
  end
end, emu.callbackType.exec, A_ST0, A_ST0, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function()
  local st = emu.getState()
  local sl = st["ppu.scanline"]
  local T = ((rd(0x177) & 0x1F) * 8 - rd(0xFC)) % 240
  local d = sl - T
  n_sw = n_sw + 1
  local q = rd(0x175)
  local cls = (q == 255) and "anim" or (q > 40 and "q>40" or "q<=40")
  local k = string.format("%s par=%d", cls, st["ppu.frameCount"] % 2)
  hist_add(h_sw, k, d)
  if arm then hist_add(h_arm, "arm line", arm.sl) end
  if d ~= 1 and #bad < 30 then
    bad[#bad+1] = string.format("f=%d switch line %d T=%d d=%+d %s arm=%s st0=%s", frame, sl, T, d, k,
      arm and (arm.sl .. "." .. arm.dot) or "none", st0 and (st0.sl .. "." .. st0.dot) or "none")
  end
  arm, st0 = nil, nil
end, emu.callbackType.exec, A_SW, A_SW, emu.memType.nesMemory, emu.cpuType.nes)
local function dump(h, title)
  local ks = {}
  for k in pairs(h) do ks[#ks+1] = k end
  table.sort(ks)
  for _, k in ipairs(ks) do
    local ds = {}
    for d in pairs(h[k]) do ds[#ds+1] = d end
    table.sort(ds)
    local parts = {}
    for _, d in ipairs(ds) do parts[#parts+1] = string.format("%+d:%d", d, h[k][d]) end
    log:write(string.format("%s [%s] %s\n", title, k, table.concat(parts, " ")))
  end
end
emu.addEventCallback(function()
  frame = frame + 1
  if frame == FRAMES or (lf and frame - lf == FRAMES) then
    log:write(string.format("stage-0 IRQs %d, switches %d\n", n_st0, n_sw))
    dump(h_sw, "switch line - T")
    dump(h_st0, "stage0")
    dump(h_arm, "arm")
    for _, b in ipairs(bad) do log:write("  " .. b .. "\n") end
    log:close(); emu.stop(0)
  end
end, emu.eventType.endFrame)
