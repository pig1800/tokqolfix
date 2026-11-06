local outdir = "D:/EMU/NES/tokqolfix/out/cdlprobe"
local frame = 0
local function onFrame()
  frame = frame + 1
  if frame ~= 300 then return end
  local data = emu.getCdlData(emu.memType.nesPrgRom)
  local f = assert(io.open(outdir .. "/cdl.bin", "wb"))
  local counts = {}
  for i = 0, 262143 do
    local v = data[i] or 0
    f:write(string.char(v))
  end
  f:close()
  local s = assert(io.open(outdir .. "/summary.txt", "w"))
  for bank = 0, 15 do
    local nz, code, dat = 0, 0, 0
    for i = bank * 16384, bank * 16384 + 16383 do
      local v = data[i] or 0
      if v ~= 0 then nz = nz + 1 end
      if v % 2 == 1 then code = code + 1 end
      if math.floor(v / 2) % 2 == 1 then dat = dat + 1 end
    end
    s:write(string.format("bank %2d: nonzero=%5d code=%5d data=%5d\n", bank, nz, code, dat))
  end
  s:close()
  emu.stop(0)
end
emu.addEventCallback(onFrame, emu.eventType.endFrame)
