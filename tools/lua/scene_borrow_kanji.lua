-- Survey build: upload_glyph is patched to RTS, so the scene CHR is never
-- modified.  At every first glyph upload for a message, dump the 8 KiB CHR
-- RAM and the message's text bank/address.
local outdir = "D:/EMU/NES/tokqolfix/out/test/borrow_kanji"
local hooks = {}
for line in io.lines("D:/EMU/NES/tokqolfix/decomp/build/kanji/fixed_hooks.inc") do
  local name, value = line:match("^(%w+)%s*=%s*%$(%x+)")
  if name then hooks[name] = tonumber(value, 16) end
end
local upload = hooks["RAM_UPLOAD_GLYPH"] or 0xB94C
local frame = 0
local log = assert(io.open(outdir .. "/index.txt", "w"))
local seen = {}
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then
    emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then
    emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4200 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
    end
  elseif frame >= 4200 and frame < 6000 then
    local phase = math.floor((frame - 4200) / 30) % 4
    if phase == 0 then emu.setInput({a=true}, 0)
    elseif phase == 2 then emu.setInput({right=true}, 0)
    else emu.setInput({a=false, right=false}, 0) end
  else
    emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0)
  end
end
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local function onUpload()
  local bank = rd(0x131)
  local addr = rd(0x132) | (rd(0x133) << 8)
  local key = string.format("%02X:%04X", bank, addr)
  if seen[key] then return end
  seen[key] = true
  local code = ((rd(0x137) & 3) << 8) | rd(0x136)
  local chr = {}
  for i = 0, 0x1FFF do chr[#chr+1] = string.char(emu.read(i, emu.memType.nesChrRam)) end
  local name = string.format("c_%05d_%02X_%04X.bin", frame, bank, addr)
  local f = assert(io.open(outdir .. "/" .. name, "wb")); f:write(table.concat(chr)); f:close()
  log:write(string.format("f=%d bank=%02X addr=%04X code=%03X\n", frame, bank, addr, code))
end
local function onFrame()
  frame = frame + 1
  if frame == 6000 then log:close(); emu.stop(0) end
end
emu.addMemoryCallback(onUpload, emu.callbackType.exec, upload, upload, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
