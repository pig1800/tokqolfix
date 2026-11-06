local outdir = "D:/EMU/NES/tokqolfix/out/run1"
local frame = 0
local function onFrame()
  frame = frame + 1
  if frame == 300 then
    local f = assert(io.open(outdir .. "/probe.txt", "w"))
    local function dump(t, name)
      f:write(name .. ":")
      for i = 0, 15 do f:write(string.format(" %02X", emu.read(i, t))) end
      f:write("\n")
    end
    dump(emu.memType.chrRam, "chrRam")
    dump(emu.memType.ppuDebug, "ppuDebug")
    dump(emu.memType.cpuDebug, "cpuDebug")
    f:write("state=" .. tostring(emu.getState()["frameCount"]) .. "\n")
    f:close()
    emu.stop(0)
  end
end
emu.addEventCallback(onFrame, emu.eventType.endFrame)
