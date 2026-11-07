-- Replay the title -> new game sequence and capture every frame around the
-- history prompt opening, plus the PPU scanline at each NMI exit (rti at $EF37).
local outdir = "D:/EMU/NES/tokqolfix/out/test/open_frames"
local frame = 0
local log = assert(io.open(outdir .. "/nmi_exit.txt", "w"))
local maxsl = -1
local function w(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then
    emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 2000 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
    end
  else
    emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
  end
end
local function onRti()
  local ok, s = pcall(emu.getState)
  local sl, cy = -999, -999
  if ok and type(s) == "table" then
    sl = s["ppu.scanline"] or (s.ppu and s.ppu.scanline) or -999
    cy = s["ppu.cycle"] or (s.ppu and s.ppu.cycle) or -999
  end
  if frame >= 900 and frame <= 1300 then
    log:write(string.format("f=%d scanline=%d cycle=%d mask=%02X\n", frame, sl, cy, emu.read(0xFE, emu.memType.nesInternalRam)))
  end
  if sl >= 0 and sl < 240 and sl > maxsl then maxsl = sl end
end
local function onFrame()
  frame = frame + 1
  if frame >= 980 and frame <= 1120 then
    w(string.format("f_%04d.png", frame), emu.takeScreenshot())
  end
  if frame == 1300 then
    log:write(string.format("max visible scanline at NMI exit: %d\n", maxsl)); log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onRti, emu.callbackType.exec, 0xEF37, 0xEF37, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
