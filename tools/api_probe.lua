local outdir = "D:/EMU/NES/tokqolfix/out/run1"
local frame = 0
local function onFrame()
  frame = frame + 1
  if frame == 120 then
    local f = assert(io.open(outdir .. "/api.txt", "w"))
    for k,v in pairs(emu) do
      f:write(tostring(k) .. " = " .. type(v) .. "\n")
    end
    f:write("--- memType\n")
    for k,v in pairs(emu.memType) do f:write(tostring(k) .. "=" .. tostring(v) .. "\n") end
    f:write("--- tries\n")
    local function t(label, fn)
      local ok, a, b = pcall(fn)
      f:write(label .. ": ok=" .. tostring(ok) .. " a=" .. tostring(a) .. " b=" .. tostring(b) .. "\n")
    end
    t("read(cpuDebug)", function() return emu.read(0x10, emu.memType.cpuDebug) end)
    t("read(cpu)", function() return emu.read(0x10, emu.memType.cpu) end)
    t("read(ppuDebug 2000)", function() return emu.read(0x2000, emu.memType.ppuDebug) end)
    t("read(0,0)", function() return emu.read(0x10, 0) end)
    t("read(256)", function() return emu.read(0x10, 256) end)
    t("readWord", function() return emu.readWord(0x10, emu.memType.cpuDebug) end)
    t("debugRead", function() return emu.debugRead(0x10, emu.memType.cpuDebug) end)
    f:close()
    emu.stop(0)
  end
end
emu.addEventCallback(onFrame, emu.eventType.endFrame)
