-- Revision-9 diagnostic: CHR reg1 switch scanlines, stack writes into the
-- RAM cell_check code at $01EC-$01F7, nmi_mode vs band flag, crash PCs,
-- and screenshots around the history prompt and after the oath.
local outdir = "D:/EMU/NES/tokqolfix/out/test/rev9diag"
local frame = 0
local log = assert(io.open(outdir .. "/diag.txt", "w"))
local chr1_n = 0
local switches = {}      -- per frame list of "scanline:value"
local stackhits = 0
local stacklog = {}
local crash = nil
local band_nmi_mode = 0
local function w(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(data); f:close()
end
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4200 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
  else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
end
local function scanline()
  local ok, s = pcall(emu.getState)
  if ok and type(s) == "table" then return s["ppu.scanline"] or -999 end
  return -999
end
local function onChr1(addr, value)
  chr1_n = chr1_n + 1
  if chr1_n == 5 then
    chr1_n = 0
    local pc = emu.getCpuState().pc
    switches[#switches+1] = string.format("%d@%04X", scanline(), pc)
  end
end
local function onStackWrite(addr, value)
  local pc = emu.getCpuState().pc
  if pc >= 0xBF00 and pc <= 0xBFFF then return end
  stackhits = stackhits + 1
  if #stacklog < 40 then
    stacklog[#stacklog+1] = string.format("f=%d pc=%04X addr=%04X", frame, pc, addr)
  end
end
local function onBadExec(addr, value)
  if crash then return end
  crash = string.format("f=%d exec at %04X", frame, addr)
  log:write("CRASH " .. crash .. "\n")
end
local function onFrame()
  frame = frame + 1
  local band = emu.read(0x01E9, emu.memType.nesMemory)
  local mode = emu.read(0x00F0, emu.memType.nesMemory)
  local busy = emu.read(0x00EC, emu.memType.nesMemory)
  if band ~= 0 and mode ~= 0 then band_nmi_mode = band_nmi_mode + 1 end
  if band ~= 0 or #switches > 0 then
    log:write(string.format("f=%d band=%d mode=%02X busy=%d sw=%s\n", frame, band, mode, busy, table.concat(switches, " ")))
  end
  switches = {}
  if (frame >= 880 and frame <= 1400 and frame % 20 == 0) or (frame >= 2250 and frame <= 4000 and frame % 25 == 0) then
    w(string.format("f%04d.png", frame), emu.takeScreenshot())
  end
  if frame == 4000 or crash then
    log:write(string.format("stack writes into $01EC-$01F7 outside trampoline: %d\n", stackhits))
    for _, s in ipairs(stacklog) do log:write("  " .. s .. "\n") end
    log:write(string.format("frames with band on and nmi_mode nonzero: %d\n", band_nmi_mode))
    if crash then log:write("crash: " .. crash .. "\n") end
    log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onChr1, emu.callbackType.write, 0xDFFF, 0xDFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onStackWrite, emu.callbackType.write, 0x01EC, 0x01F7, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onBadExec, emu.callbackType.exec, 0x0800, 0x5FFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onBadExec, emu.callbackType.exec, 0x6000, 0x7FFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onBadExec, emu.callbackType.exec, 0x0000, 0x00FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onBadExec, emu.callbackType.exec, 0x0200, 0x05FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
