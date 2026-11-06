local outdir = "D:/EMU/NES/tokqolfix/out/cdlprobe"
local frame = 0
local function onFrame()
  frame = frame + 1
  if frame ~= 180 then return end
  local f = assert(io.open(outdir .. "/probe.txt", "w"))
  for name, val in pairs(emu.memType) do
    local ok, size = pcall(emu.getMemorySize, val)
    local ok2, data = pcall(emu.getCdlData, val)
    if ok or ok2 then
      f:write(string.format("%s=%s size=%s cdl_ok=%s", name, tostring(val), tostring(ok and size or "?"), tostring(ok2)))
      if ok2 and type(data) == "table" then
        local n = 0
        for _ in pairs(data) do n = n + 1 end
        f:write(" entries=" .. n)
        for _, idx in ipairs({0, 1, 2, 0x10, 0x8000, 0x8001, 0xFFFF, 0x10000}) do
          local v = data[idx]
          if v ~= nil then f:write(string.format(" [%X]=%02X", idx, v)) end
        end
      end
      f:write("\n")
    end
  end
  f:close()
  emu.stop(0)
end
emu.addEventCallback(onFrame, emu.eventType.endFrame)
