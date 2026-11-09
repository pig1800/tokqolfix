-- Revision-12 gate: position of the hack's last PPU access in each NMI
-- (PPUADDR/PPUDATA writes and PPUDATA reads by hack-bank code; scroll
-- writes separately), per unit type.  Every PPUADDR/PPUDATA access must
-- end before the pre-render line (scanline 261); the scroll restore must
-- end before dot 257 of the pre-render line.  Standard path + town.
-- Unit entry addresses come from decomp/build/kanji/hack.lst (@ADDR@ lines
-- are rewritten by tools/garble_run.py --lua ... or edited by hand).
local A_ENTRY  = 0x800C  -- @nmi_ef08@
local A_PROBE  = 0x82D9  -- @probe_window@
local A_UPLOAD = 0x8482  -- @upload_go@
local A_POOLCHK = 0xBB74  -- @pool_check_go@
local A_RESTORE= 0x85B6  -- @restore_tile@
local A_FORCE  = 0x89E0  -- @arm_force@
local A_FORCE_END = 0x89FC  -- @arm_force_end@
local A_REPLAY = 0x8212  -- @replay_entry@
local LAST = tonumber(os.getenv("DL_FRAMES") or "6000")
-- DL_STATE: run from a save state instead of power-on, with DL_PATH steps
-- (one every 40 frames from load+30, "w" = wait) as in garble_state.lua.
local DL_STATE = os.getenv("DL_STATE")
local dl_steps = {}
for s in string.gmatch(os.getenv("DL_PATH") or "", "[^,]+") do dl_steps[#dl_steps+1] = s end
local dl_loaded, dl_lf = false, nil
local outdir = "D:/EMU/NES/tokqolfix/out/test/r12"
local log = assert(io.open(os.getenv("DL_OUT") or (outdir .. "/vblank_deadline.txt"), "w"))
local frame = 0
local function fmt(p) return string.format("sl%d.%d", p // 341, p % 341) end
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function hm() return rd(0x8000) == 0x4C and rd(0x8003) == 0x4C and rd(0x8006) == 0x4C end
local function onInput()
  if DL_STATE then
    if not dl_lf then emu.setInput({}, 0); return end
    local f = frame - dl_lf - 30
    local s = f >= 0 and dl_steps[math.floor(f / 40) + 1] or nil
    if s and s ~= "w" and (f % 40) < 3 then local i = {}; i[s] = true; emu.setInput(i, 0) else emu.setInput({}, 0) end
    return
  end
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
  elseif f >= 4330 then
    if f % 90 < 3 then emu.setInput({a=true}, 0) else emu.setInput({}, 0) end
  else emu.setInput({}, 0) end
end
local function pos()
  local s = emu.getState()
  local sl = s["ppu.scanline"]; if sl == -1 then sl = 261 end
  if sl < 100 then sl = sl + 262 end            -- past the pre-render line
  return sl * 341 + s["ppu.cycle"], s
end
local units, lastdata, lastscroll, rendering = {}, nil, nil, false
local entrypos, tier = 0, 0
local E = {}
local nmistart = nil
local H = {}
local over_data, over_scroll = 0, 0
local ex = {}
local function hackpc(pc) return ((pc >= 0x8000 and pc < 0x8C00) or (pc >= 0xB900 and pc < 0xBF00)) and hm() end
local function onEntry()
  if not hm() then return end
  units = {}; lastdata = nil; lastscroll = nil
  rendering = (rd(0xFE) & 0x18) ~= 0 and rd(0xEC) == 0
  entrypos = pos()
  local q = (rd(0x41) - rd(0x179)) & 0xFF
  local k = q == 0 and "q0" or (q <= 8 and "q1-8" or "q9+")
  if rd(0x39) ~= rd(0x17A) then k = "anim" end   -- CHR-animation step: no units
  if rendering then
    local e = E[k] or {n=0, max=0}; E[k] = e
    e.n = e.n + 1; if entrypos > e.max then e.max = entrypos end
    if entrypos >= 258 * 341 and k ~= "q9+" and k ~= "anim" and #ex < 20 then ex[#ex+1] = string.format("late entry f=%d %s %s nmi_start=%s mask=%02X fc=%02X", frame, k, fmt(entrypos), nmistart and fmt(nmistart) or "?", rd(0xFE), rd(0x33)) end
  end
end
local function mark(n) return function() if hm() then units[#units+1] = n end end end
local force_late, force_max = 0, 0
local function onData()
  local pc = emu.getCpuState().pc
  if hackpc(pc) then
    if pc >= A_FORCE and pc < A_FORCE_END then
      -- irq_arm0's address force: allowed up to pre-render dot 180
      local p = pos()
      if p > force_max then force_max = p end
      if p >= 261 * 341 + 180 then force_late = force_late + 1; if #ex < 20 then ex[#ex+1] = string.format("f=%d force %s", frame, fmt(p)) end end
    else
      lastdata = pos()
    end
  end
end
local function onScroll()
  local pc = emu.getCpuState().pc
  if hackpc(pc) then lastscroll = pos() end
end
local function onFrame()
  frame = frame + 1
  if DL_STATE and dl_loaded and not dl_lf then dl_lf = frame end
  if rendering and lastdata then
    local k = table.concat(units, "+")
    if k == "" then k = "(none)" end
    local h = H[k] or {n=0, max=0, maxs=0, cost=0}; H[k] = h
    h.n = h.n + 1
    if lastdata - entrypos > h.cost then h.cost = lastdata - entrypos end
    if lastdata > h.max then h.max = lastdata; h.f = frame end
    if lastscroll and lastscroll > h.maxs then h.maxs = lastscroll end
    if lastdata >= 261 * 341 then over_data = over_data + 1; if #ex < 20 then ex[#ex+1] = string.format("f=%d %s data %s", frame, k, fmt(lastdata)) end end
    if lastscroll and lastscroll >= 261 * 341 + 250 then over_scroll = over_scroll + 1; if #ex < 20 then ex[#ex+1] = string.format("f=%d %s scroll %s", frame, k, fmt(lastscroll)) end end
  end
  lastdata = nil; lastscroll = nil; rendering = false
  if frame == LAST then
    log:write(string.format("NMIs with a hack PPUADDR/PPUDATA/OAMDATA access after the pre-render line start: %d\n", over_data))
    log:write(string.format("NMIs with the scroll restore after pre-render dot 250: %d\n", over_scroll))
    log:write(string.format("irq_arm0 address-force writes after pre-render dot 180: %d (latest %s)", force_late, fmt(force_max)) .. string.char(10))
    for _, e in ipairs(ex) do log:write("  " .. e .. "\n") end
    for k, e in pairs(E) do log:write(string.format("  entry %-5s n=%5d max %s", k, e.n, fmt(e.max)) .. string.char(10)) end
    local ks = {}
    for k in pairs(H) do ks[#ks+1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do
      local h = H[k]
      log:write(string.format("  %-28s n=%5d last data access max %s (f=%d), last scroll write max %s, max cost from entry %d cycles", k, h.n, fmt(h.max), h.f or 0, fmt(h.maxs), h.cost // 3) .. string.char(10))
    end
    log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(function() nmistart = pos() end, emu.callbackType.exec, 0xEE79, 0xEE79, emu.cpuType.nes, emu.memType.nesMemory)
emu.addMemoryCallback(onEntry, emu.callbackType.exec, A_ENTRY, A_ENTRY, emu.cpuType.nes, emu.memType.nesMemory)
emu.addMemoryCallback(mark("probe"), emu.callbackType.exec, A_PROBE, A_PROBE, emu.cpuType.nes, emu.memType.nesMemory)
emu.addMemoryCallback(mark("upload"), emu.callbackType.exec, A_UPLOAD, A_UPLOAD, emu.cpuType.nes, emu.memType.nesMemory)
emu.addMemoryCallback(mark("restore"), emu.callbackType.exec, A_RESTORE, A_RESTORE, emu.cpuType.nes, emu.memType.nesMemory)
emu.addMemoryCallback(mark("replay"), emu.callbackType.exec, A_REPLAY, A_REPLAY, emu.cpuType.nes, emu.memType.nesMemory)
emu.addMemoryCallback(mark("poolchk"), emu.callbackType.exec, A_POOLCHK, A_POOLCHK, emu.cpuType.nes, emu.memType.nesMemory)
emu.addMemoryCallback(onData, emu.callbackType.write, 0x2004, 0x2004, emu.cpuType.nes, emu.memType.nesMemory)
if DL_STATE then
  emu.addMemoryCallback(function()
    if dl_loaded then return end
    dl_loaded = true
    local f = io.open(DL_STATE, "rb"); local d = f:read("*a"); f:close()
    emu.loadSavestate(d)
  end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
end
emu.addMemoryCallback(onData, emu.callbackType.write, 0x2006, 0x2007, emu.cpuType.nes, emu.memType.nesMemory)
emu.addMemoryCallback(onData, emu.callbackType.read, 0x2007, 0x2007, emu.cpuType.nes, emu.memType.nesMemory)
emu.addMemoryCallback(onScroll, emu.callbackType.write, 0x2005, 0x2005, emu.cpuType.nes, emu.memType.nesMemory)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
