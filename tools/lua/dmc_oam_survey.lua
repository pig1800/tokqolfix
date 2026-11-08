-- Does the game use the DMC channel, and is OAM slot 0 in use?  Original ROM,
-- standard 4000-frame input path.
local outdir = "D:/EMU/NES/tokqolfix/out/test/ramsurvey"
local frame = 0
local dmcw, dmc_on = 0, 0
local oam0 = {}
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
local function onDmc(addr, value) dmcw = dmcw + 1 end
local function onStatus(addr, value) if (value & 0x10) ~= 0 then dmc_on = dmc_on + 1 end end
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function onFrame()
  frame = frame + 1
  if frame % 10 == 0 then
    local k = string.format("%02X %02X %02X %02X", rd(0x200), rd(0x201), rd(0x202), rd(0x203))
    oam0[k] = (oam0[k] or 0) + 1
  end
  if frame == 4000 then
    local f = assert(io.open(outdir .. "/dmc_oam.txt", "w"))
    f:write(string.format("writes to $4010-$4013: %d; $4015 writes with DMC bit: %d\n", dmcw, dmc_on))
    local keys = {}
    for k in pairs(oam0) do keys[#keys+1] = k end
    table.sort(keys, function(a, b) return oam0[a] > oam0[b] end)
    for i = 1, math.min(#keys, 12) do f:write(string.format("oam0 y,t,a,x = %s  x%d\n", keys[i], oam0[keys[i]])) end
    f:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onDmc, emu.callbackType.write, 0x4010, 0x4013, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onStatus, emu.callbackType.write, 0x4015, 0x4015, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
