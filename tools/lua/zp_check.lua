-- Gate (revision 15): the kanji overlay must hand the game's $10/$11 back unchanged.
-- Snapshot at every entry from the text engine into the overlay and after
-- every frame wait; compare at every exit back to the engine and before
-- every frame wait.  Input: standard path, then the first town.
local outdir = "D:/EMU/NES/tokqolfix/out/test/r12"
local log = assert(io.open(outdir .. "/zp_check.txt", "w"))
local frame = 0
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function onInput()
  local f = frame
  if f >= 300 and f < 600 and (f % 60) < 3 then emu.setInput({start=true}, 0)
  elseif f >= 600 and f < 760 and (f % 60) < 3 then emu.setInput({a=true}, 0)
  elseif f >= 800 and f < 4200 then
    local phase = math.floor((f - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({}, 0) end
  elseif f >= 4200 and f < 4330 then
    if f % 30 < 3 then emu.setInput({a=true}, 0) else emu.setInput({}, 0) end
  elseif f >= 4330 and f < 4700 then
    if f % 90 < 3 then emu.setInput({a=true}, 0) else emu.setInput({}, 0) end
  else
    local intro = {{"down",60},{"right",40},{"down",120},{"right",30},{"left",32},{"down",150},{"left",60},{"down",100}}
    local t, g, done = f - 4700, {}, false
    for _, r in ipairs(intro) do
      if t < r[2] then g[r[1]] = true; done = true; break end
      t = t - r[2]
    end
    if not done then
      local p = math.floor((f - 5292) / 37) % 8
      local m = {{a=true},{},{a=true},{},{right=true},{a=true},{left=true},{b=true}}
      g = m[p + 1]
    end
    emu.setInput(g, 0)
  end
end
local snap = nil
local bad, checks = 0, 0
local function ov() return rd(0xB800) == 0x8E end
local function take(tag) if ov() or tag == "resume" then snap = {rd(0x10), rd(0x11), tag} end end
local function cmp(tag)
  if not snap then return end
  checks = checks + 1
  local a, b = rd(0x10), rd(0x11)
  if a ~= snap[1] or b ~= snap[2] then
    bad = bad + 1
    if bad <= 20 then log:write(string.format("f=%d %s->%s: $10/$11 %02X%02X -> %02X%02X%s", frame, snap[3], tag, snap[2], snap[1], b, a, string.char(10))) end
  end
  snap = nil
end
local function on(addr, fn) emu.addMemoryCallback(fn, emu.callbackType.exec, addr, addr, emu.memType.nesMemory, emu.cpuType.nes) end
local A_ENTRY = 0x8597  -- @msg_entry@
local A_DISPATCH = 0x8742  -- @text_dispatch@
local A_CTRL = 0x8AB6  -- @ctrl_store@
local A_WAIT = 0xFFE6  -- @wait_text@
local A_SCROLL = 0xD2AC  -- @scroll_text@
on(A_ENTRY, function() take("entry") end)
on(A_DISPATCH, function() take("dispatch") end)
on(A_CTRL, function() take("ctrl") end)
on(0xD286, function() cmp("TEXT_RETURN") end)
on(0xD2B7, function() cmp("NORMAL_CHAR") end)
on(0xD250, function() cmp("LINE_LOOP") end)
on(0xD160, function() cmp("MSG_LOOP") end)
on(0xD2CA, function() cmp("ctrl_ret") end)
on(A_WAIT, function() cmp("wait") end)
on(A_WAIT + 3, function() take("resume") end)   -- after the frame wait
on(A_SCROLL, function() cmp("scroll") end)
on(A_SCROLL + 3, function() take("resume") end)
local function onFrame()
  frame = frame + 1
  if frame >= 9000 then
    log:write(string.format("checks %d, overlay exits with $10/$11 changed: %d%s", checks, bad, string.char(10)))
    log:close(); emu.stop(0)
  end
end
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
