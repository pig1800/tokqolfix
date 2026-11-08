-- Who turns NMI off at the oath freeze?  Log PPUCTRL writes, shadow writes,
-- and executions of the RAM cell_check code (with its bytes) in frames 2470-2490.
local outdir = "D:/EMU/NES/tokqolfix/out/test/rev9diag"
local frame = 0
local log = assert(io.open(outdir .. "/nmioff.txt", "w"))
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
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function active() return frame >= 2470 and frame <= 2490 end
local function onCtrl(addr, value)
  if not active() then return end
  local c = emu.getCpuState()
  log:write(string.format("f=%d PPUCTRL<=%02X pc=%04X sp=%02X\n", frame, value, c.pc, c.sp))
end
local function onShadow(addr, value)
  if not active() then return end
  log:write(string.format("f=%d shadow<=%02X pc=%04X\n", frame, value, emu.getCpuState().pc))
end
local function onRamExec(addr)
  if not active() then return end
  if addr == 0x01EC or addr == 0x01F2 then
    local b = {}
    for i = 0, 5 do b[#b+1] = string.format("%02X", rd(addr + i)) end
    log:write(string.format("f=%d exec %04X bytes=%s sp=%02X\n", frame, addr, table.concat(b, " "), emu.getCpuState().sp))
  end
end
local function onFrame()
  frame = frame + 1
  if active() then
    local s = emu.getState()
    local ctrl = s["ppu.control"] or s["ppu.ctrl"] or -1
    log:write(string.format("f=%d end: ppuctrl_state=%s shadow=%02X\n", frame, tostring(ctrl), rd(0xFF)))
    if frame == 2470 then
      local keys = {}
      for k, v in pairs(s) do if type(k) == "string" and k:find("ppu") and (k:find("ctrl") or k:find("control") or k:find("nmi")) then keys[#keys+1] = k .. "=" .. tostring(v) end end
      log:write("ppu keys: " .. table.concat(keys, " ") .. "\n")
    end
  end
  if frame == 2491 then log:close(); emu.stop(0) end
end
emu.addMemoryCallback(onCtrl, emu.callbackType.write, 0x2000, 0x2000, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onShadow, emu.callbackType.write, 0x00FF, 0x00FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onRamExec, emu.callbackType.exec, 0x01EC, 0x01F7, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
