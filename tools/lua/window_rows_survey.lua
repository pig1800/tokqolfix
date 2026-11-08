-- Original ROM: which tile indices appear in nametable rows 18-27 (both
-- nametables) over the standard path extended into the town dialogue?
-- Buckets of 200 frames; reports upper tiles (>= $80) and tiles $6D-$7F.
local outdir = "D:/EMU/NES/tokqolfix/out/test/ramsurvey"
local frame = 0
local buckets = {}
local msgs = {}
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
  elseif frame >= 4330 and frame < 5400 then
    if frame % 90 < 3 then emu.setInput({a=true}, 0) else emu.setInput({a=false}, 0) end
  else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
end
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local function onMsg() msgs[#msgs+1] = frame end
local function onFrame()
  frame = frame + 1
  if frame >= 600 and frame % 10 == 0 then
    local b = math.floor(frame / 200) * 200
    local t = buckets[b]; if not t then t = {}; buckets[b] = t end
    for _, base in ipairs({0x2000, 0x2400}) do
      for a = base + 18 * 32, base + 28 * 32 - 1 do
        local v = ppu(a); t[v] = (t[v] or 0) + 1
      end
    end
  end
  if frame % 400 == 0 and frame >= 4000 then
    local f = assert(io.open(outdir .. string.format("/wr_%04d.png", frame), "wb")); f:write(emu.takeScreenshot()); f:close()
  end
  if frame == 5400 then
    local f = assert(io.open(outdir .. "/window_rows.txt", "w"))
    f:write("text_show_message frames: " .. table.concat(msgs, " ") .. "\n")
    local keys = {}
    for b in pairs(buckets) do keys[#keys+1] = b end
    table.sort(keys)
    for _, b in ipairs(keys) do
      local up, fr, lo = {}, {}, 0
      for v = 0, 255 do
        if buckets[b][v] then
          if v >= 0x80 then up[#up+1] = string.format("%02X", v)
          elseif v >= 0x6D then fr[#fr+1] = string.format("%02X", v)
          else lo = lo + 1 end
        end
      end
      f:write(string.format("frames %d-%d: lower(<6D) distinct %d; 6D-7F: %s; upper: %s\n", b, b + 199, lo, table.concat(fr, " "), table.concat(up, " ")))
    end
    f:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onMsg, emu.callbackType.exec, 0xD124, 0xD124, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
