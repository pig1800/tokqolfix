-- CDL capture (used for decomp step A, 2026-11-11).
-- Load CR_STATE, play CR_PATH ("A3,w30,..."; w = no input), screenshots at
-- CR_SHOTS frames (after the load), PRG CDL dump to CR_OUT/cdl.bin at CR_END.
local STATE = os.getenv("CR_STATE")
local OUTD = os.getenv("CR_OUT")
local END = tonumber(os.getenv("CR_END"))
local keymap = {U="up",D="down",L="left",R="right",A="a",B="b",S="start",E="select"}
local sched, total = {}, 0
for s in string.gmatch(os.getenv("CR_PATH") or "", "[^,]+") do
  local k, n = s:match("^(%a)(%d+)$"); n = tonumber(n)
  for i = 1, n do sched[total+i] = keymap[k] end; total = total + n
end
local shots = {}
for s in string.gmatch(os.getenv("CR_SHOTS") or "", "[^,]+") do shots[tonumber(s)] = true end
local frame, lf, loaded = 0, nil, false
emu.addMemoryCallback(function()
  if loaded then return end
  loaded = true
  if STATE and STATE ~= "" then
    local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close()
    emu.loadSavestate(d)
  end
  lf = frame
end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  local k
  if lf then local f = frame - lf; k = f >= 1 and sched[f] or nil end
  if k then local t = {}; t[k] = true; emu.setInput(t, 0) else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  frame = frame + 1
  if not lf then return end
  local f = frame - lf
  if shots[f] then
    local fh = io.open(string.format("%s/s_%04d.png", OUTD, f), "wb"); fh:write(emu.takeScreenshot()); fh:close()
  end
  if f == END then
    local n = emu.getMemorySize(emu.memType.nesPrgRom)
    local t = {}
    for i = 0, n - 1 do t[#t+1] = string.char(emu.read(i, emu.memType.nesPrgRom) and 0 or 0) end
    local data = emu.getCdlData(emu.memType.nesPrgRom)
    local o = {}
    for i = 0, n - 1 do o[#o+1] = string.char(data[i] or 0) end
    local fh = io.open(OUTD .. "/cdl.bin", "wb"); fh:write(table.concat(o)); fh:close()
    emu.stop(0)
  end
end, emu.eventType.endFrame)
