local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local function dump(tag)
  local s = emu.getState()
  local keys = {}
  for k, _ in pairs(s) do if k:find("^mapper") or k:find("^cpu%.pc") or k:find("prg") or k:find("chr") then keys[#keys+1] = k end end
  table.sort(keys)
  local f = assert(io.open(outdir .. "/mapstate_c16b" .. "_" .. tag .. ".txt", "w"))
  for _, k in ipairs(keys) do f:write(k .. "=" .. tostring(s[k]) .. "\n") end
  f:close()
end
local function onFrame()
  frame = frame + 1
  if frame == 5 then dump("f5") end
  if frame == 120 then dump("f120"); emu.stop(0) end
end
local done = false
local function afterInit()
  if done then return end
  done = true
  local v = 1
  for i = 1, 5 do emu.write(0xDFFF, v & 1, emu.memType.nesMemory); v = v >> 1 end
end
emu.addMemoryCallback(afterInit, emu.callbackType.exec, 0xF00C, 0xF00C, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
