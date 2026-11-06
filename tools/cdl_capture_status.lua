-- Capture Mesen CDL while replaying a known mid-game route (menu/town/status
-- route; exact destination depends on the current save/menu state), then dump
-- the CDL.  Use a copied ROM name so the original battery save is untouched.
local outdir = "D:/EMU/NES/tokqolfix/out/cdl_status"
local frame = 0

local function writefile(name, data)
  local f = assert(io.open(outdir .. "/" .. name, "wb"))
  f:write(data)
  f:close()
end

local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then
    emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4000 then
    if frame % 20 < 3 then emu.setInput({a=true}, 0)
    else emu.setInput({start=false,a=false,b=false,select=false,down=false}, 0) end
  elseif frame >= 4800 and frame < 4830 then emu.setInput({b=true}, 0)
  elseif frame >= 5000 and frame < 5030 then emu.setInput({start=true}, 0)
  elseif frame >= 5200 and frame < 5230 then emu.setInput({down=true}, 0)
  elseif frame >= 5300 and frame < 5330 then emu.setInput({down=true}, 0)
  elseif frame >= 5400 and frame < 5430 then emu.setInput({a=true}, 0)
  elseif frame >= 5700 and frame < 5706 then emu.setInput({down=true}, 0)
  elseif frame >= 5750 and frame < 5756 then emu.setInput({down=true}, 0)
  elseif frame >= 5850 and frame < 5856 then emu.setInput({down=true}, 0)
  elseif frame >= 5950 and frame < 5956 then emu.setInput({a=true}, 0)
  elseif frame >= 6100 and frame < 6106 then emu.setInput({a=true}, 0)
  else
    emu.setInput({start=false,a=false,b=false,select=false,down=false}, 0)
  end
end

local function onFrame()
  frame = frame + 1
  if frame == 6000 or frame == 6300 then
    writefile(string.format("s_%04d.png", frame), emu.takeScreenshot())
  end
  if frame == 6300 then
    local data = emu.getCdlData(emu.memType.nesPrgRom)
    local f = assert(io.open(outdir .. "/cdl.bin", "wb"))
    for i = 0, 262143 do f:write(string.char(data[i] or 0)) end
    f:close()
    emu.stop(0)
  end
end

emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
