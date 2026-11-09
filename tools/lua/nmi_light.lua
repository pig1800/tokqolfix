-- Original ROM: scanline at loc_EF08 split by whether this NMI flushed
-- queue bytes, uploaded the palette ($39 moved), or uploaded $03E0
-- (vram_dma_pending seen non-zero at NMI entry).
local outdir = "D:/EMU/NES/tokqolfix/out/test/ramsurvey"
local frame = 0
local log = assert(io.open(outdir .. "/nmi_light.txt", "w"))
local lastq, lastp = -1, -1
local dma_at_entry, busy_at_entry = 0, 0
local H = {}
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
local function onEntry()
  dma_at_entry = rd(0x3D) -- placeholder, replaced below
end
local function onEF08()
  local s = emu.getState()
  local sl = s["ppu.scanline"]; if sl == -1 then sl = 261 end
  local q, p = rd(0x41), rd(0x39)
  local cls
  if q == lastq and p == lastp then cls = (dma_at_entry ~= 0) and "light+dma" or "light" else cls = "busy" end
  if busy_at_entry ~= 0 then cls = "nmi_busy" end
  lastq, lastp = q, p
  local h = H[cls]; if not h then h = {}; H[cls] = h end
  h[sl] = (h[sl] or 0) + 1
end
local function onFrame()
  frame = frame + 1
  if frame == 9000 then
    for cls, h in pairs(H) do
      local keys = {}
      for k in pairs(h) do keys[#keys+1] = k end
      table.sort(keys)
      local parts = {}
      for _, k in ipairs(keys) do parts[#parts+1] = string.format("%d:%d", k, h[k]) end
      log:write(cls .. ": " .. table.concat(parts, " ") .. "\n")
    end
    log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(function() dma_at_entry = 0; busy_at_entry = rd(0xEC); if rd(0x3F) ~= 0 then dma_at_entry = rd(0x3D) end end, emu.callbackType.exec, 0xEE79, 0xEE79, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onEF08, emu.callbackType.exec, 0xEF08, 0xEF08, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
