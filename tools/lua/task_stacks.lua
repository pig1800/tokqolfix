-- Original ROM: per running task slot, the min/max SP seen at every
-- instruction fetch sampled at NMI entry and at every JSR into wait_vblank,
-- plus the saved SP values in the task table.
local outdir = "D:/EMU/NES/tokqolfix/out/test/ramsurvey"
local frame = 0
local minsp, maxsp = {}, {}
local saved = {}
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4200 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
  elseif frame >= 4200 and frame < 4330 then
    if frame % 30 < 3 then emu.setInput({a=true}, 0) else emu.setInput({a=false}, 0) end
  elseif frame >= 4330 and frame < 9000 then
    local p = math.floor((frame - 4330) / 45) % 8
    if p == 0 then emu.setInput({a=true}, 0)
    elseif p == 2 then emu.setInput({right=true}, 0)
    elseif p == 4 then emu.setInput({a=true}, 0)
    elseif p == 6 then emu.setInput({down=true}, 0)
    else emu.setInput({a=false, right=false, down=false}, 0) end
  else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
end
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function note(tag)
  local sp = emu.getCpuState().sp
  local k = tag .. string.format(" slot=%d", rd(0x32))
  if not minsp[k] or sp < minsp[k] then minsp[k] = sp end
  if not maxsp[k] or sp > maxsp[k] then maxsp[k] = sp end
end
local function onYield()
  for i = 0, 3 do
    local v = rd(0x22 + i * 4)
    local k = string.format("slot%d", i)
    saved[k] = saved[k] or {}
    saved[k][v] = true
  end
end
local function onFrame()
  frame = frame + 1
  if frame == 9000 then
    local f = assert(io.open(outdir .. "/task_stacks.txt", "w"))
    local keys = {}
    for k in pairs(minsp) do keys[#keys+1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do f:write(string.format("%s minSP=%02X maxSP=%02X\n", k, minsp[k], maxsp[k])) end
    for k, set in pairs(saved) do
      local vs = {}
      for v in pairs(set) do vs[#vs+1] = string.format("%02X", v) end
      table.sort(vs)
      f:write(k .. " saved SP values: " .. table.concat(vs, " ") .. "\n")
    end
    f:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(function() note("nmi") end, emu.callbackType.exec, 0xEE79, 0xEE79, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function() note("c343") end, emu.callbackType.exec, 0xC343, 0xC343, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function() note("write_prg") end, emu.callbackType.exec, 0xC4B7, 0xC4B7, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onYield, emu.callbackType.exec, 0xC08B, 0xC08B, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
emu.addMemoryCallback(function() note("flush") end, emu.callbackType.exec, 0xD9B3, 0xD9B3, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function() note("text_show") end, emu.callbackType.exec, 0xD124, 0xD124, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function() note("put_tile") end, emu.callbackType.exec, 0xD340, 0xD340, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function() note("render_cell") end, emu.callbackType.exec, 0xDBCA, 0xDBCA, emu.memType.nesMemory, emu.cpuType.nes)
