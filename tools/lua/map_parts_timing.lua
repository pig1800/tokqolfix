-- Map-mode part switches (2026-11-14, TEXT_RENDERER.md "IRQ"): every IRQ sequence from stage 0 to
-- the next NMI.  Per write (cv_w1, the R0 data store; cv_last's store):
-- line and dot of the write cycle.  Skips (cv_stage's bne cv_quit taken:
-- nmi_busy | KANJI_MAINCHR).  Sequences that do not give exactly lines
-- 71, 119, 167 in dots 257-320 and 240 are listed.
-- Env: PB_STATE (optional), PB_PATH, PB_RAMIMG, PB_STD (1: stdc2's inputs
-- from power-on), PB_END, PB_OUT
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
local function pos(add)
  local s = emu.getState()
  local sl, dot = s["ppu.scanline"], s["ppu.cycle"] + add
  if sl == -1 then sl = 261 end
  while dot > 340 do dot = dot - 341; sl = sl + 1 end
  return sl, dot
end
local NMI = 0xEE79               -- the game's NMI entry (vector $FFFA)
local CV_IRQ = 0x7900  -- @cv_irq@
local CV_STAGE = 0x7920  -- @cv_stage@
local CV_W1 = 0x794D  -- @cv_w1@
local CV_LAST = 0x7953  -- @cv_last@
local CV_BNE = CV_STAGE + 10     -- "bne cv_quit" (A = nmi_busy | KANJI_MAINCHR)
local CV_LASTW = CV_LAST + 7     -- cv_last's "sta MMC3_DATA"
local seq = nil
local hist, lasth = {}, {}
local nseq, nok, nskip, bad = 0, 0, 0, {}
local function close()
  if not seq then return end
  if seq.st == 2 and lf then
    nseq = nseq + 1
    local ok = #seq.w == 3 and seq.last ~= nil and not seq.skip
    local want = {71, 119, 167}
    if ok then
      for i = 1, 3 do
        local w = seq.w[i]
        if w[1] ~= want[i] or w[2] < 257 or w[2] > 320 then ok = false end
      end
    end
    if seq.skip then nskip = nskip + 1 end
    if ok then nok = nok + 1
    else
      local t = {}
      for _, w in ipairs(seq.w) do t[#t+1] = string.format("%d.%d", w[1], w[2]) end
      bad[#bad+1] = string.format("f%d stage0 %d.%d writes [%s] last %s%s", frame - lf, seq.s0[1], seq.s0[2],
        table.concat(t, " "), seq.last and string.format("%d.%d", seq.last[1], seq.last[2]) or "-",
        seq.skip and string.format(" SKIP at %d.%d busy %02X mainchr %02X", seq.skip[1], seq.skip[2], seq.skip[3], seq.skip[4]) or "")
    end
  end
  seq = nil
end
emu.addMemoryCallback(function() close() end, emu.callbackType.exec, NMI, NMI, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function()
  local st = R(0x0170)
  if st == 1 or st == 2 then
    close()
    local sl, dot = pos(0)
    seq = {st = st, s0 = {sl, dot}, w = {}}
  end
end, emu.callbackType.exec, CV_IRQ, CV_IRQ, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function()
  if not seq then return end
  local a = emu.getState()["cpu.a"]
  if a ~= 0 and not seq.skip then
    local sl, dot = pos(0)
    seq.skip = {sl, dot, R(0xEC), R(0x0103)}
  end
end, emu.callbackType.exec, CV_BNE, CV_BNE, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function()
  local sl, dot = pos(9)
  if seq then seq.w[#seq.w+1] = {sl, dot} end
  local k = string.format("line %3d dot %3d", sl, dot)
  hist[k] = (hist[k] or 0) + 1
end, emu.callbackType.exec, CV_W1, CV_W1, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function()
  local sl, dot = pos(9)
  if seq then seq.last = {sl, dot} end
  local k = string.format("line %3d", sl)
  lasth[k] = (lasth[k] or 0) + 1
end, emu.callbackType.exec, CV_LASTW, CV_LASTW, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  frame = frame + 1
  if lf and frame - lf == END then
    local o = io.open(os.getenv("PB_OUT"), "w")
    o:write(string.format("sequences %d ok %d skips %d not-ok %d\n", nseq, nok, nskip, #bad))
    local t = {}; for k, v in pairs(hist) do t[#t+1] = k .. ": " .. v end; table.sort(t)
    o:write("-- R0 writes (line, dot of the write cycle)\n" .. table.concat(t, "\n") .. "\n")
    t = {}; for k, v in pairs(lasth) do t[#t+1] = k .. ": " .. v end; table.sort(t)
    o:write("-- line-240 writes\n" .. table.concat(t, "\n") .. "\n-- not ok\n")
    for i = 1, math.min(#bad, 400) do o:write(bad[i] .. "\n") end
    o:close(); emu.stop(0)
  end
end, emu.eventType.endFrame)
