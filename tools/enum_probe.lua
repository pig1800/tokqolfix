local outdir = "D:/EMU/NES/tokqolfix/out/cdlprobe"
local frame = 0
local function onFrame()
  frame = frame + 1
  if frame ~= 5 then return end
  local f = assert(io.open(outdir .. "/enums.txt", "w"))
  for _, name in ipairs({"callbackType", "memCallbackType", "cpuType", "eventType", "memType"}) do
    f:write("--- " .. name .. "\n")
    local t = emu[name]
    if t then
      for k, v in pairs(t) do f:write(tostring(k) .. "=" .. tostring(v) .. "\n") end
    else
      f:write("(nil)\n")
    end
  end
  f:close()
  emu.stop(0)
end
emu.addEventCallback(onFrame, emu.eventType.endFrame)
