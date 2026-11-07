local outdir = "D:/EMU/NES/tokqolfix/out/test"
local frame = 0
local function dump(tag)
  local s = emu.getState()
  local keys = {}
  for k, _ in pairs(s) do if k:find("^mapper") or k:find("^cpu%.pc") or k:find("prg") or k:find("chr") then keys[#keys+1] = k end end
  table.sort(keys)
  local f = assert(io.open(outdir .. "/mapstate_c16" .. "_" .. tag .. ".txt", "w"))
  for _, k in ipairs(keys) do f:write(k .. "=" .. tostring(s[k]) .. "\n") end
  f:close()
end
local function onFrame()
  frame = frame + 1
  if "c16" == "c16" and frame == 1 then
    local v = 1
    for i = 1, 5 do emu.write(0xDFFF, v & 1, emu.memType.nesMemory); v = v >> 1 end
  end
  if frame == 5 then dump("f5") end
  if frame == 120 then dump("f120"); emu.stop(0) end
end
emu.addEventCallback(onFrame, emu.eventType.endFrame)
