-- Load the known dialogue save state, advance the dialogue, and dump CDL.
local outdir = "D:/EMU/NES/tokqolfix/out/cdl_state"
local statepath = "D:/EMU/NES/SaveStates/Tenchi o Kurau (Japan) (Rev 1)_11.mss"
local frame = 0
local loaded = false

local function writefile(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb"))
  f:write(data)
  f:close()
end

local function onExec(addr, value)
  if loaded then return end
  loaded = true
  local f = io.open(statepath, "rb")
  if not f then return end
  local data = f:read("*a")
  f:close()
  emu.loadSavestate(data)
end

local function onInput()
  if frame < 60 then
    emu.setInput({}, 0)
  elseif frame % 30 < 3 then
    emu.setInput({a=true}, 0)
  else
    emu.setInput({a=false, b=false, start=false, select=false,
                  up=false, down=false, left=false, right=false}, 0)
  end
end

local function onFrame()
  frame = frame + 1
  if frame == 300 or frame == 600 or frame == 900 then
    writefile(string.format("s_%04d.png", frame), emu.takeScreenshot())
  end
  if frame == 900 then
    local data = emu.getCdlData(emu.memType.nesPrgRom)
    local f = assert(io.open(outdir .. "/cdl.bin", "wb"))
    for i = 0, 262143 do f:write(string.char(data[i] or 0)) end
    f:close()
    emu.stop(0)
  end
end

emu.addMemoryCallback(onExec, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
